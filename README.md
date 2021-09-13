# bzfilelist_diff
Compares two .dat files from the Backblaze.pzpkg/bzdata/bzfilelists directory, ignoring lines starting with '#'.  
Useful for checking what happened between two lists from the same drive at different points in time.  
Missing, new and changed files will be written to new lists (in the same format as the .dat files) in the output directory.

### Usage:
    bzfilelist_diff [option ...] <old file> <new file> <output directory>

### Options:
    -f           Overwrite files in output directory if they already exists.
    -l <number>  Specify the number of lines to load simultaneously. Larger numbers may increase or decrease memory usage. Default is 10000.

### Example:
    bzfilelist_diff old/v0000_root_filelist.dat new/v0000_root_filelist.dat diff/
