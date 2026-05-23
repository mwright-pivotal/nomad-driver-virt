#!/bin/bash
# Debug script for nomad-driver-virt plugin issues

set -e

echo "=== Nomad Driver Virt Debug Script ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "WARNING: Not running as root. Some checks may fail."
    echo ""
fi

# 1. Check plugin binary
echo "1. Checking plugin binary..."
if [ -f "./nomad-driver-virt" ]; then
    ls -lh ./nomad-driver-virt
    file ./nomad-driver-virt
    echo "✓ Plugin binary exists"
else
    echo "✗ Plugin binary not found!"
    exit 1
fi
echo ""

# 2. Check architecture
echo "2. Checking system architecture..."
uname -m
echo ""

# 3. Check libvirt
echo "3. Checking libvirt..."
if command -v virsh &> /dev/null; then
    virsh version
    echo ""
    echo "Testing libvirt connection..."
    if virsh -c qemu:///system list &> /dev/null; then
        echo "✓ Libvirt connection successful"
    else
        echo "✗ Libvirt connection failed!"
    fi
else
    echo "✗ virsh command not found!"
fi
echo ""

# 4. Check QEMU/KVM
echo "4. Checking QEMU/KVM..."
if [ -f "/usr/libexec/qemu-kvm" ]; then
    ls -lh /usr/libexec/qemu-kvm
    /usr/libexec/qemu-kvm --version
    echo "✓ QEMU emulator found"
else
    echo "✗ QEMU emulator not found at /usr/libexec/qemu-kvm"
fi
echo ""

# 5. Check dependencies
echo "5. Checking shared library dependencies..."
ldd ./nomad-driver-virt | grep "not found" && echo "✗ Missing dependencies!" || echo "✓ All dependencies satisfied"
echo ""

# 6. Check Nomad
echo "6. Checking Nomad..."
if command -v nomad &> /dev/null; then
    nomad version
else
    echo "✗ nomad command not found!"
fi
echo ""

# 7. Check for running plugin process
echo "7. Checking for running plugin process..."
ps aux | grep nomad-driver-virt | grep -v grep || echo "No plugin process currently running"
echo ""

# 8. Check plugin logs
echo "8. Checking plugin logs..."
if [ -d "/tmp" ]; then
    echo "Recent plugin log files:"
    find /tmp -name "plugin*" -type f -mtime -1 2>/dev/null | while read file; do
        echo "  $file"
        echo "  Size: $(du -h "$file" | cut -f1)"
    done
fi
echo ""

# 9. Check SELinux
echo "9. Checking SELinux..."
if command -v getenforce &> /dev/null; then
    getenforce
    if [ "$(getenforce)" != "Disabled" ]; then
        echo "Checking recent SELinux denials..."
        ausearch -m avc -ts recent 2>/dev/null | grep nomad || echo "No recent SELinux denials for nomad"
    fi
else
    echo "SELinux tools not available"
fi
echo ""

echo "=== Debug Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Build with debug symbols:"
echo "   go build -gcflags='all=-N -l' -o nomad-driver-virt"
echo ""
echo "2. Check Nomad logs for plugin errors:"
echo "   sudo journalctl -u nomad -f"
echo "   # or"
echo "   sudo tail -f /var/log/nomad/nomad.log"
echo ""
echo "3. Check plugin-specific logs:"
echo "   sudo find /tmp -name 'plugin*' -type f -mtime -1 -exec ls -lh {} \;"
echo "   sudo cat /tmp/plugin*/stderr"
echo ""
echo "4. To attach debugger to running plugin:"
echo "   PID=\$(pgrep nomad-driver-virt)"
echo "   sudo dlv attach \$PID --headless --listen=:2345 --api-version=2"
echo ""
echo "5. See REMOTE_DEBUGGING.md for complete debugging guide"

# Made with Bob
