# BashScriptHub

A centralized repository of portable, well-documented Bash scripts for DevOps, ITOps, and SecOps workflows.

![License](https://img.shields.io/badge/License-MIT-green)
![Shell](https://img.shields.io/badge/Shell-Bash-blue)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey)
![Scripts](https://img.shields.io/badge/Scripts-53-orange)
![Status](https://img.shields.io/badge/Status-Active-brightgreen)

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Script Categories](#script-categories)
  - [Automation Scripts](#automation-scripts)
  - [Cloud Provider Scripts](#cloud-provider-scripts)
  - [Container Scripts](#container-scripts)
  - [Monitoring Scripts](#monitoring-scripts)
  - [Networking Scripts](#networking-scripts)
  - [Provisioning Scripts](#provisioning-scripts)
  - [Security Scripts](#security-scripts)
  - [User Management Scripts](#user-management-scripts)
  - [Utility Scripts](#utility-scripts)
- [Common Design Patterns](#common-design-patterns)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Cross-Platform Compatibility**: Works across Debian/Ubuntu, RHEL/CentOS, and Fedora/Rocky/Alma Linux distributions
- **Package Manager Detection**: Automatically detects and uses the appropriate package manager (apt, yum, dnf)
- **Idempotent Design**: Scripts are designed to be safely run multiple times
- **Comprehensive Logging**: Color-coded output and detailed logging capabilities
- **Robust Error Handling**: Graceful failure modes and informative error messages
- **Well-Documented**: Detailed usage instructions and examples for each script

## Compatibility

| Distribution       | Support |
|--------------------|---------|
| Debian/Ubuntu      | ✅      |
| RHEL/CentOS 7+     | ✅      |
| Fedora             | ✅      |
| Rocky Linux/Alma   | ✅      |
| Amazon Linux 2     | ✅      |
| Oracle Linux       | ✅      |
| Arch Linux         | ⚠️      |
| Alpine Linux       | ⚠️      |

Note: ⚠️ indicates partial support or may require additional configuration

## Repository Structure

```
bashscript-hub/
├── automation/     # Scripts for task automation
├── cloud/          # Cloud provider management scripts
├── containers/     # Container and orchestration scripts
├── monitoring/     # System and service monitoring
├── networking/     # Network management and diagnostics
├── provisioning/   # System setup and configuration
├── security/       # Security auditing and hardening
├── user-management/# User account operations
└── utils/          # General utility scripts
```

## Getting Started

Most scripts can be run directly after marking them as executable:

```bash
chmod +x script_name.sh
./script_name.sh --help
```

Many scripts also support sourcing for using their functions in other scripts:

```bash
source utils/color_echo.sh
log_info "This is an information message"
```

## Script Categories

### Automation Scripts ✅

All automation scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [auto_backup.sh](automation/auto_backup.sh) | Automate file/directory backups with retention policies |
| [auto_update_packages.sh](automation/auto_update_packages.sh) | Safely update system packages across distributions |
| [cleanup_old_logs.sh](automation/cleanup_old_logs.sh) | Clean up old log files based on age or size |
| [cronjob_creator.sh](automation/cronjob_creator.sh) | Create and manage cron jobs with validation |
| [deploy_app.sh](automation/deploy_app.sh) | Streamlined application deployment with rollback support |
| [mass_ssh_command_runner.sh](automation/mass_ssh_command_runner.sh) | Run commands on multiple servers via SSH |

### Cloud Provider Scripts ✅

All cloud provider scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [aws_cli_helpers.sh](cloud/aws_cli_helpers.sh) | Helper functions for AWS CLI operations |
| [aws_ec2_reboot.sh](cloud/aws_ec2_reboot.sh) | Safely reboot AWS EC2 instances with various options |
| [aws_s3_sync.sh](cloud/aws_s3_sync.sh) | Sync files to/from AWS S3 buckets |
| [azure_blob_cleanup.sh](cloud/azure_blob_cleanup.sh) | Clean up old blobs in Azure Storage containers |
| [azure_vm_stats.sh](cloud/azure_vm_stats.sh) | Collect and display Azure VM statistics |
| [gcp_snapshot_rotation.sh](cloud/gcp_snapshot_rotation.sh) | Manage GCP disk snapshots with rotation policy |
| [gcp_vm_inventory.sh](cloud/gcp_vm_inventory.sh) | Create detailed inventory of GCP virtual machines |

### Container Scripts ✅

All container scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [docker_cleanup.sh](containers/docker_cleanup.sh) | Clean up Docker containers, volumes, and networks |
| [docker_image_prune.sh](containers/docker_image_prune.sh) | Clean up unused Docker images with safety options |
| [docker_monitor.sh](containers/docker_monitor.sh) | Monitor Docker container resource usage |
| [k8s_node_status.sh](containers/k8s_node_status.sh) | Check Kubernetes node status and resource usage |
| [k8s_pod_log_collector.sh](containers/k8s_pod_log_collector.sh) | Collect logs from Kubernetes pods |
| [k8s_restart_pod.sh](containers/k8s_restart_pod.sh) | Safely restart Kubernetes pods |

### Monitoring Scripts ✅

All monitoring scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [cpu_mem_monitor.sh](monitoring/cpu_mem_monitor.sh) | Monitor CPU and memory usage with alerts |
| [disk_usage_alert.sh](monitoring/disk_usage_alert.sh) | Monitor disk usage and send alerts |
| [http_response_checker.sh](monitoring/http_response_checker.sh) | Check HTTP response status and performance |
| [process_uptime_report.sh](monitoring/process_uptime_report.sh) | Report on process uptime and restarts |
| [service_checker.sh](monitoring/service_checker.sh) | Check service status and perform actions |
| [ssl_expiry_checker.sh](monitoring/ssl_expiry_checker.sh) | Check SSL certificate expiry dates |

### Networking Scripts ✅

All networking scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [bandwidth_usage_monitor.sh](networking/bandwidth_usage_monitor.sh) | Monitor network bandwidth usage |
| [check_dns_latency.sh](networking/check_dns_latency.sh) | Check DNS resolution latency |
| [firewall_rules_report.sh](networking/firewall_rules_report.sh) | Generate firewall rules report |
| [ip_blacklist_checker.sh](networking/ip_blacklist_checker.sh) | Check if IPs are blacklisted |
| [port_scanner.sh](networking/port_scanner.sh) | Basic port scanning and service detection |
| [trace_route_logger.sh](networking/trace_route_logger.sh) | Log trace routes over time |

### Provisioning Scripts ✅

All provisioning scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [configure_ntp.sh](provisioning/configure_ntp.sh) | Configure NTP services across distributions |
| [install_ansible.sh](provisioning/install_ansible.sh) | Install and configure Ansible |
| [install_docker.sh](provisioning/install_docker.sh) | Install and configure Docker |
| [install_jenkins.sh](provisioning/install_jenkins.sh) | Install and configure Jenkins |
| [install_kubernetes.sh](provisioning/install_kubernetes.sh) | Install and configure Kubernetes |
| [install_prometheus_grafana.sh](provisioning/install_prometheus_grafana.sh) | Install Prometheus and Grafana |
| [install_terraform.sh](provisioning/install_terraform.sh) | Install and configure Terraform |
| [setup_basic_firewall.sh](provisioning/setup_basic_firewall.sh) | Set up basic firewall rules |
| [setup_zsh_ohmyzsh.sh](provisioning/setup_zsh_ohmyzsh.sh) | Install Zsh and Oh My Zsh |

### Security Scripts ⚠️

Three security scripts have been implemented. The remaining scripts are planned for future implementation.

| Script | Status | Description |
|--------|--------|-------------|
| [failed_login_alert.sh](security/failed_login_alert.sh) | ✅ | Monitor and alert on failed login attempts |
| [file_integrity_checker.sh](security/file_integrity_checker.sh) | ✅ | Basic file integrity checking |
| [ssh_hardening.sh](security/ssh_hardening.sh) | ✅ | Apply SSH security hardening |
| [auditd_rules_applier.sh](security/auditd_rules_applier.sh) | 🔄 | Apply auditd rules for system auditing |
| [password_expiry_checker.sh](security/password_expiry_checker.sh) | 🔄 | Check password expiry for accounts |
| [rootkit_scan_wrapper.sh](security/rootkit_scan_wrapper.sh) | 🔄 | Wrapper for rootkit scanning tools |
| [system_audit.sh](security/system_audit.sh) | 🔄 | Perform basic system security audit |

### User Management Scripts ⚠️

Three user management scripts have been implemented. The remaining scripts are planned for future implementation.

| Script | Status | Description |
|--------|--------|-------------|
| [create_users_bulk.sh](user-management/create_users_bulk.sh) | ✅ | Create multiple user accounts from CSV |
| [password_policy_checker.sh](user-management/password_policy_checker.sh) | ✅ | Check password policy compliance |
| [reset_user_password.sh](user-management/reset_user_password.sh) | ✅ | Reset user passwords safely |
| [expire_old_users.sh](user-management/expire_old_users.sh) | 🔄 | Expire old user accounts |
| [group_audit.sh](user-management/group_audit.sh) | 🔄 | Audit user groups and memberships |
| [list_locked_users.sh](user-management/list_locked_users.sh) | 🔄 | List locked user accounts |

### Utility Scripts ✅

All utility scripts are fully implemented and tested.

| Script | Description |
|--------|-------------|
| [color_echo.sh](utils/color_echo.sh) | Colored logging functions for bash scripts |
| [csv_to_json.sh](utils/csv_to_json.sh) | Convert CSV files to JSON format |
| [file_watcher.sh](utils/file_watcher.sh) | Watch files for changes and execute commands |
| [get_public_ip.sh](utils/get_public_ip.sh) | Get public IP address using various methods |
| [json_parser.sh](utils/json_parser.sh) | Parse and manipulate JSON from bash |
| [log_rotation.sh](utils/log_rotation.sh) | Rotate log files with compression |

## Common Design Patterns

### Package Manager Detection
```bash
# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt-get"
    PKG_INSTALL="$PKG_MANAGER install -y"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
    PKG_INSTALL="$PKG_MANAGER install -y"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    PKG_INSTALL="$PKG_MANAGER install -y"
else
    echo "No supported package manager found"
    exit 1
fi
```

### Color Output and Logging
```bash
# Source the color_echo utility
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$ROOT_DIR/utils/color_echo.sh" ]; then
    source "$ROOT_DIR/utils/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
fi
```

### Command Availability Checking
```bash
# Check if required commands are available
check_requirements() {
    local missing_cmds=()
    
    for cmd in curl jq grep; do
        if ! command -v $cmd &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Please install the required packages for your distribution"
        exit 1
    fi
}
```

## Contributing

Contributions to improve this repository are welcome. Please fork the repository, create a new branch for your feature or bug fix, make your changes, and submit a pull request with a clear description of your modifications.

Please ensure your scripts follow the established patterns and include proper documentation.

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/Shwet-Kamal-Singh/vpn/blob/main/LICENSE) file for details.

![Original Creator](https://img.shields.io/badge/Original%20Creator-Shwet%20Kamal%20Singh-blue)

![License](https://img.shields.io/badge/License-MIT-green)

## Contact

For any inquiries or permissions, please contact:
- Email: shwetkamalsingh55@gmail.com
- LinkedIn: https://www.linkedin.com/in/shwet-kamal-singh/
- GitHub: https://github.com/Shwet-Kamal-Singh