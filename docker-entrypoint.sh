#!/bin/bash
set -e

HPC_USER="${HPC_USER:-student}"
HPC_UID="${HPC_UID:-2000}"
HPC_GID="${HPC_GID:-2000}"
HPC_HOME="/home/${HPC_USER}"

ensure_hpc_user() {
    if ! getent group "${HPC_USER}" >/dev/null 2>&1; then
        groupadd -g "${HPC_GID}" "${HPC_USER}"
    fi

    if ! id -u "${HPC_USER}" >/dev/null 2>&1; then
        useradd -m -u "${HPC_UID}" -g "${HPC_GID}" -s /bin/bash "${HPC_USER}"
    fi

    mkdir -p "${HPC_HOME}"
    chown "${HPC_UID}:${HPC_GID}" "${HPC_HOME}" 2>/dev/null || true
    chmod 700 "${HPC_HOME}" 2>/dev/null || true
    chmod 755 /home 2>/dev/null || true
    # Keep account valid for key-based SSH on Rocky/RHEL images.
    if passwd -S "${HPC_USER}" 2>/dev/null | awk '{print $2}' | grep -q '^L$'; then
        tmp_pass="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
        echo "${HPC_USER}:${tmp_pass:-hpc-temporary-password}" | chpasswd >/dev/null 2>&1 || true
    fi
    passwd -u "${HPC_USER}" >/dev/null 2>&1 || true
    chage -E -1 -M -1 -I -1 -m 0 "${HPC_USER}" >/dev/null 2>&1 || true
}

init_hpc_ssh() {
    local ssh_dir="${HPC_HOME}/.ssh"
    local key_file="${ssh_dir}/id_ed25519"

    mkdir -p "${ssh_dir}"
    chmod 700 "${ssh_dir}"
    chown "${HPC_UID}:${HPC_GID}" "${ssh_dir}" 2>/dev/null || true

    if [ ! -f "${key_file}" ]; then
        gosu "${HPC_USER}" ssh-keygen -t ed25519 -N "" -f "${key_file}"
    fi

    # Keep public and authorized keys in sync with the private key in shared HOME.
    gosu "${HPC_USER}" ssh-keygen -y -f "${key_file}" > "${key_file}.pub"
    cp -f "${key_file}.pub" "${ssh_dir}/authorized_keys"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown "${HPC_UID}:${HPC_GID}" "${key_file}" "${key_file}.pub" "${ssh_dir}/authorized_keys" 2>/dev/null || true

    cat > "${ssh_dir}/config" <<EOF
Host slurmctld c1 c2
    User ${HPC_USER}
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    PubkeyAuthentication yes
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
EOF
    chmod 600 "${ssh_dir}/config"
    chown "${HPC_UID}:${HPC_GID}" "${ssh_dir}/config" 2>/dev/null || true

    : > "${ssh_dir}/known_hosts"
    for host in slurmctld c1 c2; do
        ssh-keyscan "${host}" >> "${ssh_dir}/known_hosts" 2>/dev/null || true
    done
    chmod 600 "${ssh_dir}/known_hosts" 2>/dev/null || true
    chown "${HPC_UID}:${HPC_GID}" "${ssh_dir}/known_hosts" 2>/dev/null || true
    chown -R "${HPC_UID}:${HPC_GID}" "${ssh_dir}" 2>/dev/null || true
    chmod 700 "${ssh_dir}" 2>/dev/null || true
    chmod 600 "${ssh_dir}/id_ed25519" "${ssh_dir}/authorized_keys" "${ssh_dir}/config" "${ssh_dir}/known_hosts" 2>/dev/null || true
    chmod 644 "${ssh_dir}/id_ed25519.pub" 2>/dev/null || true
}

start_sshd() {
    if command -v /usr/sbin/sshd >/dev/null 2>&1; then
        mkdir -p /var/run/sshd
        mkdir -p /var/log
        /usr/sbin/sshd -E /var/log/sshd.log
    fi
}

ensure_hpc_user

echo "---> Starting the MUNGE Authentication service (munged) ..."
gosu munge /usr/sbin/munged

if [ "$1" = "slurmdbd" ]
then
    echo "---> Starting the Slurm Database Daemon (slurmdbd) ..."

    # Substitute environment variables in slurmdbd.conf
    envsubst < /etc/slurm/slurmdbd.conf > /etc/slurm/slurmdbd.conf.tmp
    mv /etc/slurm/slurmdbd.conf.tmp /etc/slurm/slurmdbd.conf
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chmod 600 /etc/slurm/slurmdbd.conf

    # Wait for MySQL using environment variables directly
    until echo "SELECT 1" | mysql -h mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} 2>&1 > /dev/null
    do
        echo "-- Waiting for database to become active ..."
        sleep 2
    done
    echo "-- Database is now active ..."

    exec gosu slurm /usr/sbin/slurmdbd -Dvvv
    # exec tail -f /dev/null
fi

if [ "$1" = "slurmctld" ]
then
    init_hpc_ssh
    start_sshd

    echo "---> Waiting for slurmdbd to become active before starting slurmctld ..."

    until 2>/dev/null >/dev/tcp/slurmdbd/6819
    do
        echo "-- slurmdbd is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmdbd is now active ..."

    echo "---> Starting the Slurm Controller Daemon (slurmctld) ..."
    exec gosu slurm /usr/sbin/slurmctld -i -Dvvv
fi

if [ "$1" = "slurmrestd" ]
then
    echo "---> Waiting for slurmctld to become active before starting slurmrestd ..."

    until 2>/dev/null >/dev/tcp/slurmctld/6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    echo "---> Starting the Slurm REST API Daemon (slurmrestd) ..."
    # Run slurmrestd on both Unix socket and network port
    # Unix socket provides passwordless local access
    # Note: slurmrestd should NOT be run as SlurmUser or root (security requirement)
    mkdir -p /var/run/slurmrestd
    chown slurmrest:slurmrest /var/run/slurmrestd
    exec gosu slurmrest /usr/sbin/slurmrestd -vvv unix:/var/run/slurmrestd/slurmrestd.socket 0.0.0.0:6820
fi

if [ "$1" = "slurmd" ]
then
    init_hpc_ssh
    start_sshd

    echo "---> Waiting for slurmctld to become active before starting slurmd..."

    until 2>/dev/null >/dev/tcp/slurmctld/6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    # Extract container name from cgroup path
    # Docker Compose sets container name to c1, c2, etc.
    # We can find this in the cgroup path
    CONTAINER_NAME=""

    # Try reading from /proc/self/cgroup (works in cgroup v1 and v2)
    if [ -f /proc/self/cgroup ]; then
        # Extract container name from cgroup path
        # Format: 0::/docker/<container_id> or similar
        CONTAINER_NAME=$(cat /proc/self/cgroup | sed -n 's|.*/docker/\([^/]*\).*|\1|p' | head -1)
    fi

    # If we got a container ID, try to resolve it to a name using the host's /proc
    if [ -n "$CONTAINER_NAME" ] && [ -d "/host_proc" ]; then
        # Try to find the container name by looking at cmdline or environ
        # This is a fallback - we'll use the cgroup container ID to query Docker
        echo "---> Container ID from cgroup: $CONTAINER_NAME"
    fi

    # Fallback: try to extract from /proc/1/cpuset which often contains container name
    if [ -z "$CONTAINER_NAME" ] || [ ${#CONTAINER_NAME} -eq 64 ]; then
        # We only have a container ID, need the actual name
        # Try cpuset path which may have the name
        if [ -f /proc/1/cpuset ]; then
            CPUSET_PATH=$(cat /proc/1/cpuset)
            # Extract last component which might be container name
            CONTAINER_NAME=$(basename "$CPUSET_PATH")
            echo "---> Container name from cpuset: $CONTAINER_NAME"
        fi
    fi

    # If container name looks like c1, c2, use it directly
    if [[ "$CONTAINER_NAME" =~ ^c[0-9]+$ ]]; then
        echo "---> Using container name as hostname: $CONTAINER_NAME"
        hostname "$CONTAINER_NAME"
    else
        echo "---> WARNING: Could not determine proper container name"
        echo "---> Got: $CONTAINER_NAME"
        echo "---> Using fallback hostname"
    fi

    NODE_HOSTNAME=$(hostname)
    echo "---> Final hostname: $NODE_HOSTNAME"
    echo "---> Starting the Slurm Node Daemon (slurmd) as $NODE_HOSTNAME..."
    exec /usr/sbin/slurmd -Dvvv
fi

exec "$@"
