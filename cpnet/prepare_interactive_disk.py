#!/usr/bin/env python3
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
WORK = os.path.join(HERE, "zout", "interactive")
os.makedirs(WORK, exist_ok=True)

IMG_MAXI = os.environ.get("IMG_MAXI", os.path.expanduser("~/Downloads/SW1711-I8.imd"))
BIOS_CIM = os.path.join(ROOT, "rcbios-in-c", "clang", "bios.clang.cim")
CPNET_DIST = os.path.expanduser("~/git/cpnet-z80/dist")
MAME_DIR = os.environ.get("MAME_DIR", os.path.normpath(os.path.join(ROOT, "..", "mame")))
FLOPTOOL = os.path.join(MAME_DIR, "floptool")
CPMCP = os.path.expanduser("~/.local/bin/cpmcp")
FORMAT = "rc702-8dd"

DISK_IMD = os.path.join(WORK, "disk.imd")
DISK_MFI = os.path.join(WORK, "disk.mfi")

print(f"1. Copying base image from {IMG_MAXI}...")
subprocess.run(["cp", IMG_MAXI, DISK_IMD], check=True)

print("2. Patching BIOS...")
subprocess.run(["python3", os.path.join(ROOT, "rcbios", "patch_bios.py"), DISK_IMD, BIOS_CIM], check=True)

print("3. Building SNIOS variants...")
subprocess.run(["python3", os.path.join(HERE, "build_snios.py")], check=True)

print("4. Injecting CP/NET SPR and COM files...")
env = dict(os.environ, PATH=f"{os.path.expanduser('~/.local/bin')}:{os.environ.get('PATH', '')}")

for name in ["SNIOS.SPR", "SNIOSSIO.SPR", "SNIOSPIO.SPR"]:
    src = os.path.join(HERE, "zout", name)
    subprocess.run([CPMCP, "-f", FORMAT, DISK_IMD, src, f"0:{name}"], check=True, env=env)

import glob
for f in sorted(glob.glob(os.path.join(CPNET_DIST, "*.com")) + glob.glob(os.path.join(CPNET_DIST, "*.spr"))):
    name = os.path.basename(f).upper()
    subprocess.run([CPMCP, "-f", FORMAT, DISK_IMD, f, f"0:{name}"], check=True, env=env)

print("5. Creating AUTO.SUB and $$$.SUB...")
# Commands to execute in sequence
commands = [
    "CPNETLDR",
    "LOGIN PASSWORD",
    "NETWORK H:=I:",
    "H:",
    "DIR",
]

# Write AUTO.SUB with CR+LF line endings
auto_sub_path = os.path.join(WORK, "AUTO.SUB")
with open(auto_sub_path, "wb") as f:
    for cmd in commands:
        f.write(cmd.encode("ascii") + b"\r\n")

subprocess.run([CPMCP, "-f", FORMAT, DISK_IMD, auto_sub_path, "0:AUTO.SUB"], check=True, env=env)

# Write $$$.SUB for automatic boot execution in CP/M 2.2
# CP/M 2.2 CCP executes $$$.SUB from the last 128-byte record backward.
# Each record: byte 0 = len(command), followed by command ASCII, padded to 128 bytes with 0.
def make_rec(cmd):
    b = cmd.encode("ascii")
    assert len(b) <= 127
    return bytes([len(b)]) + b + bytes(127 - len(b))

# Reverse the command list so the first command is at the end of the file
sub_bin_path = os.path.join(WORK, "$$$.SUB")
with open(sub_bin_path, "wb") as f:
    for cmd in reversed(commands):
        f.write(make_rec(cmd))

# Remove any old 48300$.sub or existing $$$.SUB if present
subprocess.run([os.path.expanduser("~/.local/bin/cpmrm"), "-f", FORMAT, DISK_IMD, "0:$$$.SUB"], stderr=subprocess.DEVNULL, env=env)
subprocess.run([os.path.expanduser("~/.local/bin/cpmrm"), "-f", FORMAT, DISK_IMD, "0:48300$.SUB"], stderr=subprocess.DEVNULL, env=env)

# Inject $$$.SUB
subprocess.run([CPMCP, "-f", FORMAT, DISK_IMD, sub_bin_path, "0:$$$.SUB"], check=True, env=env)

print("6. Converting to MFI...")
subprocess.run([FLOPTOOL, "flopconvert", "auto", "mfi", DISK_IMD, DISK_MFI], check=True)

print("7. Verifying disk directory...")
res = subprocess.run([os.path.expanduser("~/.local/bin/cpmls"), "-f", FORMAT, DISK_IMD], capture_output=True, text=True, check=True, env=env)
print(res.stdout)

print("Done! Ready for MAME.")
