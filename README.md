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
Usage: ./yt-summarizer.sh [OPTIONS] <YouTube_URL> [api_key]

Download YouTube transcript and generate AI summary using Claude.

OPTIONS:
    -l LANG     Primary language for subtitles [default: pl]
                Common codes: pl, en, es, fr, de, it, ru, ja, ko
    -o FILE     Save summary to specified file (prints to console by default)
    -h          Show this help message

EXAMPLES:
    ./yt-summarizer.sh 'https://youtube.com/watch?v=VIDEO_ID'
                                        # Polish transcript → Polish summary
    ./yt-summarizer.sh -l en 'https://youtube.com/watch?v=VIDEO_ID'  
                                        # English transcript → English summary
    ./yt-summarizer.sh -l es -o summary.txt 'https://youtube.com/watch?v=VIDEO_ID'
                                        # Spanish transcript → Spanish summary in file
    ./yt-summarizer.sh -o /tmp/sum.txt 'https://youtu.be/VIDEO_ID'
                                        # Polish summary saved to /tmp/sum.txt

API KEY SOURCES (in order of priority):
    1. Command line argument (second parameter after URL)
    2. ANTHROPIC_API_KEY environment variable
    3. CLAUDE_API_KEY environment variable  
    4. ~/.claude_api_key file
    5. Interactive prompt

BEHAVIOR:
    - Tries primary language subtitles first
    - Falls back to English + translation if primary language unavailable
    - Auto-detects empty subtitle files and switches to fallback
    - Supports all major YouTube URL formats
```

