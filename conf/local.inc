BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"
EXTRA_IMAGE_FEATURES:append:pn-bbb-image = " ssh-server-dropbear tools-debug"
