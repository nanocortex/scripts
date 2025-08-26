# Various scripts

## Download latest Debian ISO

```bash
Usage: ./download_debian.sh [OPTIONS]

Download the latest Debian ISO for amd64 architecture.

OPTIONS:
    -t TYPE     ISO type (netinst, DVD-1, CD-1) [default: netinst]
    -d DIR      Download directory [default: ~/Downloads]
    -s          Skip checksum verification
    -m          Skip mirror speed testing (use default mirror)
    -h          Show this help message

EXAMPLES:
    ./download_debian.sh                    # Download netinst ISO to ~/Downloads
    ./download_debian.sh -t DVD-1           # Download DVD ISO
    ./download_debian.sh -d /tmp -t netinst # Download to /tmp directory
    ./download_debian.sh -s                 # Skip checksum verification
    ./download_debian.sh -m                 # Skip mirror testing
```

## Summarize YouTube video via Claude

```bash
Usage: ./yt-summarizer.sh [OPTIONS] <YouTube_URL> [claude_api_key]
Example: ./yt-summarizer.sh 'https://youtube.com/watch?v=VIDEO_ID'
Example: ./yt-summarizer.sh -o summary.txt 'https://youtube.com/watch?v=VIDEO_ID'
Example: ./yt-summarizer.sh -l en 'https://youtube.com/watch?v=VIDEO_ID'

Options:
  -l, --language LANG  Primary language for subtitles (default: pl)
                       Common: pl, en, es, fr, de, it, ru, ja, ko
  -o, --output FILE    Save summary to specified file
  -h, --help          Show this help message

API key can be provided as:
  - Second argument (after URL)
  - CLAUDE_API_KEY environment variable
  - ANTHROPIC_API_KEY environment variable
  - ~/.claude_api_key file
```

