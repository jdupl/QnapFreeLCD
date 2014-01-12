QnapFreeLCD
===========
Original author Dirk Brenken (dibdot@gmail.com)

Modified by Justin Duplessis (drfoliberg@gmail.com)

WARNING
========
This is a developer version, at the time of writing it was only tested on a TS-439 and TS-509 PRO.
Even though I use it in my productive environment, I strongly recommend that you only use it for further testing and debugging.
This script is only for QNAP-devices which running debian (possibly ubuntu)(stock QNAP firmware currently not supported!).

SCOPE
======
This script does (should do ;-) the following:
- read input for LCD status messages from a separate helper script (see sample function library)
- display status messages on LCD panel
- auto-cycling through status messages
- non-blocking manual navigation via LCD frontpanel buttons between messages
- fully configurable input-, message-,display- cycles & timeouts

REQUIREMENTS
=============
- QNAP device with LCD display & debian (possibly ubuntu)
- required debian packages (apt-get install): ksh
- optional debian packages (if you would like to use the distributed function library sample): hddtemp

GET STARTED
============
- Make this script executable (chmod 755).
- Adjust path & timeout parameters to your needs (see comments for all configurable options below)
- Rename & adjust distributed sample function library script to your needs
- Start this script ...

CHANGELOG
==========
version 0.1: initial test release

version 0.2: fix trap/exit issues

version 0.3: fixed data refresh when lcd is off

TODO
=====
- add back mdadm support alongside zfs
- run moar tests!

