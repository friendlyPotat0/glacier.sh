# glacier.sh

Does a backup from a given list of directories to a specified storage path.

### Features

-   Checks data integrity to avoid loss of information.
-   Generates logs for streamlined error debugging.
-   Backup is not compressed, allows for easier interaction with data.

### Configuration

Create under project's root directory: `configuration/source-paths.txt`, `configuration/storage-path.txt`

```
.
├── paths
│   ├── source-paths.txt
│   └── storage-path.txt
├── README.md
├── documentation.txt
└── glacier.sh
```

-   `source-paths.txt`: Locations to back up
-   `storage-path.txt`: Location to store backup

> Configuration files support tilde and global variable expansion

### TODO

Information is on the **Projects** tab of this repo.
