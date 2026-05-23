# Remote Go Debugging Setup for nomad-driver-virt

## Important: Nomad Plugin Architecture

Nomad plugins use the HashiCorp go-plugin framework and **cannot run standalone**. They must be launched by Nomad itself via the plugin system. The plugin communicates with Nomad over gRPC.

## ⚠️ s390x Architecture Limitation

**Delve does NOT support s390x architecture.** If you're on s390x (IBM Z), you must use alternative debugging methods:
- GDB (Method 4 below)
- Enhanced logging (Method 3 below)
- Printf debugging
- Remote development on amd64/arm64 system

## Prerequisites (for amd64/arm64 only)

1. Install Delve on the remote server:
```bash
go install github.com/go-delve/delve/cmd/dlv@latest
```

2. Ensure the `dlv` binary is in your PATH:
```bash
export PATH=$PATH:$(go env GOPATH)/bin
```

## Method 1: Attach Delve to Running Plugin Process

This is the most reliable method for debugging Nomad plugins.

### On the Remote Server:

1. Build the plugin with debug symbols:
```bash
go build -gcflags="all=-N -l" -o nomad-driver-virt
```

2. Copy plugin to Nomad's plugin directory:
```bash
sudo cp nomad-driver-virt /opt/nomad/plugins/
# or wherever your plugin_dir is configured
```

3. Start Nomad (or restart if already running):
```bash
sudo systemctl restart nomad
# or
sudo nomad agent -config=/etc/nomad.d/nomad.hcl
```

4. Find the plugin process ID:
```bash
ps aux | grep nomad-driver-virt
# Look for the actual plugin process, not the parent Nomad process
```

5. Attach Delve to the running process:
```bash
sudo dlv attach <PID> --headless --listen=:2345 --api-version=2 --accept-multiclient
```

### On Your Local Machine:

1. Forward the port via SSH:
```bash
ssh -L 2345:localhost:2345 user@remote-server
```

2. In VS Code, create `.vscode/launch.json`:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Attach to Remote Plugin",
            "type": "go",
            "request": "attach",
            "mode": "remote",
            "remotePath": "/home/admin/nomad-driver-virt",
            "port": 2345,
            "host": "localhost",
            "showLog": true,
            "trace": "verbose"
        }
    ]
}
```

3. Set breakpoints and start debugging (F5)

## Method 2: Debug Plugin Startup with Wrapper Script

This method allows debugging from the moment Nomad launches the plugin.

### On the Remote Server:

1. Build with debug symbols:
```bash
go build -gcflags="all=-N -l" -o nomad-driver-virt
```

2. Create a wrapper script `nomad-driver-virt-wrapper`:
```bash
#!/bin/bash
# Wait for debugger to attach
exec /usr/bin/dlv exec /opt/nomad/plugins/nomad-driver-virt.real \
    --headless \
    --listen=:2345 \
    --api-version=2 \
    --accept-multiclient \
    --continue \
    -- "$@"
```

3. Rename and setup:
```bash
sudo mv /opt/nomad/plugins/nomad-driver-virt /opt/nomad/plugins/nomad-driver-virt.real
sudo cp nomad-driver-virt-wrapper /opt/nomad/plugins/nomad-driver-virt
sudo chmod +x /opt/nomad/plugins/nomad-driver-virt
```

4. Restart Nomad:
```bash
sudo systemctl restart nomad
```

5. The plugin will wait for debugger - connect from VS Code as in Method 1

**Note**: Remove `--continue` flag if you want the plugin to wait for you to manually continue execution.

## Method 3: Enhanced Logging (Easiest Method)

If remote debugging is too complex, use extensive logging:

1. Set Nomad log level to TRACE in `/etc/nomad.d/nomad.hcl`:
```hcl
log_level = "TRACE"
```

2. Restart Nomad:
```bash
sudo systemctl restart nomad
```

3. Monitor Nomad logs in real-time:
```bash
# For systemd
sudo journalctl -u nomad -f

# For direct log files
sudo tail -f /var/log/nomad/nomad.log
```

4. Check plugin-specific logs:
```bash
# Plugin stderr/stdout are redirected to temp files
sudo ls -la /tmp/plugin*
sudo cat /tmp/plugin*/stderr
sudo cat /tmp/plugin*/stdout

# Or find them
sudo find /tmp -name "plugin*" -type f -mtime -1
```

5. Add debug logging to the code:
```go
// In providers/libvirt/libvirt.go Init() function
p.logger.Error("DEBUG: Starting Init()")
p.logger.Error("DEBUG: URI is", "uri", p.uri)
// etc.
```

## Method 4: GDB Debugging (s390x Compatible)

GDB works on all architectures including s390x. This is your best option for s390x systems.

### Setup:

1. Install GDB:
```bash
sudo dnf install gdb
```

2. Build with debug symbols:
```bash
go build -gcflags="all=-N -l" -o nomad-driver-virt
```

3. Copy to plugin directory:
```bash
sudo cp nomad-driver-virt /opt/nomad/plugins/
```

4. Start/restart Nomad:
```bash
sudo systemctl restart nomad
```

5. Find the plugin process:
```bash
PID=$(pgrep nomad-driver-virt)
echo "Plugin PID: $PID"
```

6. Attach GDB:
```bash
sudo gdb -p $PID
```

### Useful GDB Commands:

```gdb
# Set breakpoint
(gdb) break providers/libvirt/libvirt.go:1119

# Continue execution
(gdb) continue

# Print variable
(gdb) print variableName

# Show backtrace
(gdb) backtrace
(gdb) bt full

# Step through code
(gdb) next    # Next line
(gdb) step    # Step into function
(gdb) finish  # Finish current function

# List source code
(gdb) list

# Detach without killing process
(gdb) detach
(gdb) quit
```

### Remote GDB via SSH:

```bash
# On remote server
sudo gdb -p $PID
(gdb) target remote :1234

# On local machine
ssh -L 1234:localhost:1234 user@remote-server
gdb
(gdb) target remote localhost:1234
```

## Troubleshooting the Current Error

The "End of file while reading data: Input/output error" suggests:

1. **Plugin crash during initialization** - Check:
```bash
# Look for core dumps
ls -la /tmp/core*
dmesg | tail -50

# Check if plugin process starts and dies
ps aux | grep nomad-driver-virt
```

2. **Communication protocol mismatch** - Verify:
```bash
# Check Nomad version
nomad version

# Ensure plugin is built for correct architecture
file ./nomad-driver-virt
```

3. **Permissions issue** - Check:
```bash
# Verify plugin is executable
ls -la nomad-driver-virt
chmod +x nomad-driver-virt

# Check SELinux (if enabled)
getenforce
ausearch -m avc -ts recent
```

4. **Library dependencies** - Check:
```bash
# Verify all shared libraries are available
ldd ./nomad-driver-virt
```

## Quick Debug Commands

```bash
# Run plugin directly to see immediate errors
./nomad-driver-virt

# Run with strace to see system calls
strace -f ./nomad-driver-virt 2>&1 | tee plugin-trace.log

# Check for libvirt connectivity
virsh version
virsh list --all

# Test libvirt connection
virsh -c qemu:///system capabilities
```

## Firewall Configuration (if needed)

```bash
# Allow Delve port
firewall-cmd --add-port=2345/tcp --permanent
firewall-cmd --reload