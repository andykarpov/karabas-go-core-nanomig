# NanoMig (Amiga 500) core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

An Amiga 500 (OCS / ECS) for the Karabas Go family of boards. It is a port of
[NanoMig](https://github.com/harbaum/NanoMig) by Till Harbaum, which is the
[Minimig](https://en.wikipedia.org/wiki/Minimig) of the MiSTer project (Minimig-AGA, OCS / ECS
chipset only) with the TG68K CPU, to the Xilinx Spartan-6 XC6SLX25 of the Karabas boards.

| Board | Core file | Video | Audio |
|---|---|---|---|
| Karabas Go | `nanomig.kg1` | VGA, 720x576 50 Hz (31 kHz) | I2S DAC (PCM5102) |
| Karabas Mini | `nanomig.kg2` | HDMI, 720x576 50 Hz | HDMI, analog output (sigma-delta) |
| Karabas Mini G | `nanomig.kg3` | HDMI, 720x576 50 Hz | HDMI, I2S DAC |

The core files are in `src/`. They contain no Kickstart or other copyrighted data.

## What it does

- **CPU:** 68000 (TG68K) at the speed of an A500.
- **Chipset:** OCS as in the A500 or A1000, or ECS (OSD item Chipset).
- **Memory:** Chip RAM 512 KB to 2 MB, Slow RAM ("trapdoor" RAM at $C00000) none to 1.5 MB,
  Fast RAM (Zorro II, autoconfig) none, 2, 4 or 8 MB. Chip and Slow RAM are in the SRAM of the
  board, Fast RAM in its SDRAM.
- **Kickstart:** any 256 or 512 KB Kickstart ROM file from the SD card.
- **Floppy drives:** DF0 to DF3, ADF images on the SD card, read and write.
- **Hard disks:** IDE as in the A600 (Gayle): the CF card slot of the board, or HDF images on the
  SD card (two drives: master and slave).
- **Clock:** the battery-backed clock of an A500 with a memory expansion (MSM6242B), kept by the
  clock of the board.
- **Input:** USB keyboard and mouse, two joysticks (the joysticks of the board or USB gamepads).
- **Video:** PAL or NTSC, through the scan doubler of the Minimig (Amber) to 31 kHz.
- **Audio:** Paula stereo with the 4.5 kHz low-pass filter of the A500.
- **Physical floppy drive** (Karabas Go only): see [below](#physical-floppy-drive-karabas-go).

Not there: AGA (A1200), 68020 and faster CPUs, a turbo floppy, extended ADFs / IPF / SCP images,
HD floppies, the serial and parallel ports.

## Getting started

1. Copy `nanomig.kg1` (Go), `nanomig.kg2` (Mini) or `nanomig.kg3` (Mini G) to the root of the SD
   card of the board.
2. Put a Kickstart ROM on the SD card as `/amiga/kick.rom` (see [Kickstart](#kickstart)).
3. Put your ADF (and HDF) images on the SD card, for example into `/amiga`.
4. Choose Nanomig in the core menu. The Amiga starts with the Kickstart and waits for a disk:
   open the OSD with **Menu+Esc**, choose an image for DF0 (or press **Menu+F1**).

"Menu" is the Windows key of the keyboard.

## OSD menu

**Menu+Esc** opens and closes the menu (on a joystick: Start+C). The items:

| Item | Values | Hotkey |
|---|---|---|
| DF0 ... DF3 | ADF image of the floppy drive | Menu+F1 ... Menu+F4 |
| HDD0 | Off / CF card / HDF0: what IDE device 0 (master) is | |
| HDF0 | HDF image of IDE device 0 (with HDD0 = HDF0) | Menu+F5 |
| HDF1 | HDF image of IDE device 1 (slave) | Menu+F6 |
| Kickstart | Kickstart ROM file | |
| Chipset | OCS-A500 / OCS-A1000 / ECS | |
| Chip RAM | 512K / 1M / 1.5M / 2M | |
| Slow RAM | None / 512K / 1M / 1.5M | |
| Fast RAM | None / 2M / 4M / 8M | |
| Video | PAL / NTSC | |
| Reset | resets the Amiga | Ctrl+Alt+Del |

- The defaults are those of an A500 with the A501 expansion: OCS-A500, 512 KB Chip RAM, 512 KB Slow
  RAM, no Fast RAM, PAL, HDD0 = CF card.
- The settings and the chosen images are saved in the core file and come back at the next start.
- Chipset and memory take effect at the next reset (Reset item, Ctrl+Alt+Del or F12).
- In the file browser of an image item, Enter chooses a file, Esc goes back. **Del** or
  **Backspace** on the item, or `[ Eject ]` at the top of the browser, removes the image. The
  browser of an empty drive opens where the last image was chosen, on the file after it (disk 2
  after disk 1).
- **Ctrl+Alt+Backspace** (joystick: Start+X) restarts the board and goes back to the core menu.

## Kickstart

The Kickstart is not included: it is copyrighted (it is sold, for example, in Cloanto's Amiga
Forever). The core loads the file of the OSD item Kickstart, `/amiga/kick.rom` by default, at its
start and whenever another file is chosen; the Amiga is held in reset while it loads.

- 256 KB (1.2, 1.3) and 512 KB (2.0 and later) files work. A 256 KB Kickstart is mirrored in the
  upper 256 KB, as on the A500.
- The file has to be a plain ROM image as it is in the chip (big endian), not an encrypted Amiga
  Forever ROM (which needs `rom.key`) and not a byte-swapped one.
- Which one:
  - **1.3** (34.5, A500): the most compatible for games and demos. It has no IDE driver, so no
    hard disk.
  - **2.05** (37.350, A600) or **3.1** (40.063, A600): for hard disks and Workbench 2 / 3. These
    have the `scsi.device` for the Gayle IDE. The 3.1 ROMs of the A500 / A2000 do not have it and
    see no hard disk.

## Floppy disks

- The images are ADF files of 880 KB (DD). Up to four drives.
- An image chosen in the OSD is a disk put into the drive; the Amiga notices the change as with a
  real drive. Writes go to the ADF on the SD card.
- **Number of drives:** DF0 is always there. DF1 to DF3 exist up to the highest drive with an image
  when the Amiga is reset (Kickstart looks for the drives only at its start). So to have a DF1,
  choose an image for it and reset. An empty drive costs Chip RAM, and some A500 games do not run
  with external drives at all, so leave DF1-DF3 empty for those.
- The floppy speed is that of a real drive. The sectors come from the SD card through the
  microcontroller of the board.
- Disk change: Menu+F1 ... Menu+F4 opens the browser of the drive right away.

## Hard disks

The IDE interface is the Gayle of the A600. It needs Kickstart 2.05 or 3.1 (A600 versions, see
above). The OSD item HDD0 says what IDE device 0 (master) is:

- **CF card:** the CF card in the CF slot of the board. The card is accessed directly (PIO mode 0)
  and its data are laid out as on an A600, so a card prepared in WinUAE or used in an A600 works.
- **HDF0:** the HDF image of the item HDF0.
- **Off:** no device 0.

Device 1 (slave) is the HDF image of the item HDF1, if there is one. With HDD0 = CF card that is
the card plus an image.

HDF images:
- Use HDF images with an RDB ("full drive" / "RDB" hardfiles), as `scsi.device` mounts only
  partitions of an RDB. A plain "partition" hardfile without an RDB is not mounted.
- The geometry comes from the RDB; without one (an empty image) 16 heads and 63 sectors.
- An image is read and written a sector at a time through the microcontroller, so it is slower
  than the CF card.
- The size of the image is not limited by the core, but see the 4 GB limit below.

### Preparing a CF card or an HDF image

The simplest way works on any computer: an empty card or image, partitioned and formatted on the
Amiga itself with HDToolBox (see [Installing Workbench](#installing-workbench-31-on-a-hard-disk)).

- Use a CF card of at most 4 GB, or keep the partitions within the first 4 GB: `scsi.device` of
  Kickstart 2.05 / 3.1 cannot go past 4 GB.
- **An empty CF card.** HDToolBox writes its RDB over the PC partition table, so clear the card
  first:
  - Windows: `diskpart`, `list disk`, `select disk N` (the CF card: check the size!), `clean`.
  - Linux: `sudo wipefs -a /dev/sdX` (the CF card: check with `lsblk`!).
  
  After the Amiga has partitioned it, Windows offers to format the card: do not.
- **An empty HDF image** of, say, 512 MB:
  - Linux / macOS: `truncate -s 512M wb31.hdf` (or `dd if=/dev/zero of=wb31.hdf bs=1M count=512`).
  - Windows: `fsutil file createnew wb31.hdf 536870912`, or "Create hardfile" in WinUAE.
- **Prepared on a PC:** an HDF made and installed in WinUAE or FS-UAE (an A600 configuration:
  68000, Kickstart 3.1 A600, IDE drive of the A600 / Gayle, the hardfile in "full drive / RDB"
  mode) can be copied to the SD card and used as HDF0 / HDF1. Such an image can also be written to
  a CF card that is at least as big: Linux `sudo dd if=wb31.hdf of=/dev/sdX bs=1M conv=fsync`,
  Windows Win32 Disk Imager (rename it to `.img`). WinUAE, run as administrator, can also use the
  CF card in a card reader directly as an IDE drive.

### Installing Workbench 3.1 on a hard disk

You need Kickstart 3.1 (A600) and the Workbench 3.1 ADFs (Install, Workbench, Locale, Extras,
Fonts, Storage). The same works with 2.05 / Workbench 2.1.

1. OSD: Kickstart = the 3.1 ROM; HDD0 = CF card (an empty card in the slot), or HDD0 = HDF0 with an
   empty HDF in HDF0. Fast RAM 2M or more helps. DF0 = Install3.1.adf. Reset.
2. The Amiga boots the Install disk. Open the disk, the drawer HDTools, start HDToolBox.
3. The drive is listed as "Unknown". Change Drive Type, Define New, Read Configuration, OK, OK.
4. Partition Drive: for example DH0 of 200 MB for the system and DH1 of the rest. The file system
   is the Fast File System; MaxTransfer 0x1FE00 is a safe value for IDE (Advanced Options, Change
   File System). OK, then Save Changes to Drive, quit HDToolBox.
5. Reset (OSD). On the Workbench of the Install disk: select the icon DH0:NDOS, menu Icons,
   Format Disk, name it "Workbench", Quick Format, Format. The same for DH1.
6. Open the drawer Install3.1, the icon of your language, Install, follow it, install to DH0:.
   Put in the disks it asks for with Menu+F1 (Workbench3.1, Locale, Extras, Fonts, Storage).
7. Eject DF0 (Menu+F1, `[ Eject ]`) and reset: the Amiga starts from the hard disk.

Workbench 1.3 cannot be installed on a hard disk here: Kickstart 1.3 has no IDE driver.

## Physical floppy drive (Karabas Go)

The Karabas Go has the 34-pin floppy connector of a PC / Shugart drive. A real drive on it can be
an Amiga drive: in the browser of DF0 ... DF3 the entries `[ Physical DF0 ]` and `[ Physical DF1 ]`
make that DF the drive on select line 0 or 1 of the connector. **This is work in progress and
not in the release yet.**

- **Physical DF0** is the drive on DS0 (pin 10), **Physical DF1** the one on DS1 (pin 12). A PC
  3.5" drive is set to DS1 by the factory, so on a straight (not twisted) cable it is Physical
  DF1. A Gotek or a Shugart drive can be jumpered to DS0 or DS1. Both share the motor line
  (pin 16).
- Use 3.5" DD disks: the Amiga reads and writes DD (880 KB) only.
- The connector has no disk change line (pin 34), so the core emulates it. A disk taken out is
  noticed while the drive runs (no index pulses); a disk put in is noticed when the Amiga looks
  for one (it steps the head every few seconds and the core then turns the motor on briefly). To
  be safe after swapping disks, choose `[ Physical DFn ]` again in the OSD: that is a disk change
  for the Amiga.
- Copy-protected originals read like on a real Amiga as far as the data separator of the core
  (from [RobSmithDev's MiSTer floppy](https://mister.robsmithdev.co.uk)) allows.

## Keyboard

The USB keyboard is an Amiga keyboard. The keys that differ:

| PC key | Amiga |
|---|---|
| Left Win / Right Win | Left Amiga / Right Amiga |
| Left Alt / Right Alt | Left Alt / Right Alt |
| Left Ctrl | Ctrl (Right Ctrl is not used) |
| End, Insert | Help |
| Page Down | Right Amiga |
| Home / Page Up | numeric keypad ( / ) |
| Delete | Del |
| ` (left of 1) | ` |
| Caps Lock | Caps Lock (a toggle, like the Amiga key) |
| F1 ... F10 | F1 ... F10 |
| F12 | reset of the Amiga while it is held |
| Numeric keypad | numeric keypad |

The Windows keys are also the Menu key of the board: Menu+Esc, Menu+F1 ... F6 go to the OSD, not to
the Amiga. The key repeat is that of AmigaOS (the keyboard does not repeat keys itself).

Reset: **F12** (held), **Ctrl+Alt+Del** or the OSD item Reset.

## Mouse and joysticks

- The USB mouse is in Amiga port 1 (the mouse port).
- The left joystick of the board (or the first USB gamepad) is Amiga port 2, the joystick port
  that games use.
- The right joystick is Amiga port 1, together with the mouse: port 1 becomes the joystick when
  its fire button is pressed and the mouse again on the left mouse button.
- Buttons: A = fire, B = second fire button, C and Start = buttons 3 and 4.
- USB gamepads are mapped by the firmware (`drivers/*.ini` on the SD card).

## Clock

The Amiga sees the clock of an A500 memory expansion (MSM6242B at $DC0000). It runs from the
battery-backed clock of the board.

- Kickstart 2.0 and later read it at boot. Setting the time in Prefs / Time (or `SetClock SAVE`)
  sets the clock of the board.
- With Workbench 1.3 put `SetClock LOAD` into `S:Startup-Sequence`.

## Building

The core is built with Xilinx ISE 14.7 on Linux: `src/build_go.sh`, `src/build_mini.sh`,
`src/build_minig.sh` (one at a time: they share the work directories). They need the sibling repo
[karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this one for
`make_core.py`. The simulations (ISim) are in `src/sim`. `CLAUDE.md` has the details of the design
and of the tests.

The board firmware with the file mounter is
[karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware) (master).

## Credits and license

- [NanoMig](https://github.com/harbaum/NanoMig): Till Harbaum.
- Minimig: Dennis van Weeren, Jakub Bednarski and many others; MiSTer Minimig-AGA: Sorgelig and
  contributors.
- TG68K: Tobias Gubener.
- Floppy data separator: RobSmithDev ([MiSTer floppy](https://mister.robsmithdev.co.uk)).
- Amber scan doubler from the Minimig.
- Karabas Go boards and the port: Andy Karpov.

The Minimig, NanoMig, Amber and floppy sources are under the GNU GPL v3, TG68K under the GNU LGPL
v3 (see the headers of the files); see `LICENSE` for the rest.
