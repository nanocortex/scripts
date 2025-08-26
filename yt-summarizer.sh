#!/usr/bin/env sh

set -e
set +m # Disable job control messages

# Configuration constants
readonly TIMEOUT_SECONDS=10
readonly MAX_TOKENS=1000
readonly CLAUDE_MODEL="claude-opus-4-1-20250805"
readonly ANTHROPIC_API_VERSION="2023-06-01"
readonly TEMP_PREFIX="yt-summarizer"
readonly DEFAULT_LANGUAGE="pl"

# Color codes and UI functions
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
print_info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }
print_success() { printf "${GREEN}✓${NC} %s\n" "$1"; }
print_warning() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
print_error() { printf "${RED}✗${NC} %s\n" "$1"; }

start_spinner() {
  printf "${CYAN}"
  { while :; do for s in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do
    printf "\r${CYAN}%s${NC} %s" "$s" "$1"
    sleep 0.1
  done; done & } 2>/dev/null
  SPINNER_PID=$!
  disown
}
stop_spinner() {
  if [ -n "$SPINNER_PID" ]; then
    kill $SPINNER_PID 2>/dev/null
    SPINNER_PID=""
  fi
  printf "\r\033[K"
}

# Error handling
die() {
  stop_spinner 2>/dev/null || true
  print_error "$1"
  exit "${2:-1}"
}

# Input validation
validate_youtube_url() {
  case "$1" in
    *youtube.com/watch?v=* | *youtu.be/* | *youtube.com/shorts/*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_file_path() {
  local dir
  dir=$(dirname "$1")
  [ -d "$dir" ] && [ -w "$dir" ]
}

# Utility functions
find_srt_file() {
  local lang="$1"
  find "$TEMP_DIR" -name "*.$lang.srt" -type f 2>/dev/null | head -n 1
}

has_text_content() {
  local srt_file="$1"
  [ -s "$srt_file" ] && awk 'NR>=3 && !/^[0-9]+$/ && !/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ && NF>0 {print; exit}' "$srt_file" | grep -q .
}

get_language_name() {
  local lang_code="$1"
  case "$lang_code" in
    pl) echo "Polish" ;;
    en) echo "English" ;;
    es) echo "Spanish" ;;
    fr) echo "French" ;;
    de) echo "German" ;;
    it) echo "Italian" ;;
    ru) echo "Russian" ;;
    ja) echo "Japanese" ;;
    ko) echo "Korean" ;;
    *) echo "$lang_code" ;;
  esac
}

get_api_key() {
  local api_key="$1"
  if [ -n "$api_key" ]; then
    echo "$api_key"
  elif [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "$ANTHROPIC_API_KEY"
  elif [ -n "$CLAUDE_API_KEY" ]; then
    echo "$CLAUDE_API_KEY"
  elif [ -f "$HOME/.claude_api_key" ]; then
    cat "$HOME/.claude_api_key"
  else
    printf "Enter Claude API key: "
    read -r api_key
    echo "$api_key"
  fi
}

download_with_spinner() {
  local message="$1"
  local url="$2"
  local lang="$3"

  start_spinner "$message"
  if download_subtitles "$url" "$lang"; then
    stop_spinner
    return 0
  else
    stop_spinner
    return 1
  fi
}

create_temp_file() {
  local suffix="$1"
  echo "$TEMP_DIR/${TEMP_PREFIX}-$suffix"
}

save_result() {
  local transcript_file="$1"
  local use_translation="$2"
  echo "$transcript_file|$use_translation" >"$(create_temp_file "result")"
}

load_result() {
  cat "$(create_temp_file "result")"
}

validate_subtitle_content() {
  local lang="$1"
  local srt_file

  srt_file=$(find_srt_file "$lang")
  if [ -n "$srt_file" ] && has_text_content "$srt_file"; then
    echo "$srt_file"
    return 0
  else
    return 1
  fi
}

# Complete YouTube transcript downloader and summarizer with Claude
check_dependencies() {
  start_spinner "Checking dependencies..."

  if ! command -v yt-dlp >/dev/null 2>&1; then
    die "yt-dlp not installed"
  fi

  if ! command -v jq >/dev/null 2>&1; then
    die "jq not installed (needed for JSON processing). Install with: apt install jq (Ubuntu) or brew install jq (Mac)"
  fi

  stop_spinner
  print_success "Dependencies OK"
}

get_video_title() {
  local url="$1"
  local title
  title=$(timeout "$TIMEOUT_SECONDS" yt-dlp --get-title "$url" 2>/dev/null || echo "video")
  if [ -n "$title" ] && [ "$title" != "video" ]; then
    # Sanitize filename: remove problematic characters
    echo "$title" | sed 's/[<>:"/\\|?*]//g' | sed 's/[^[:print:]]//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
  else
    echo "video"
  fi
}

download_subtitles() {
  local url="$1"
  local lang="$2"
  local temp_log
  temp_log=$(create_temp_file "$lang.log")

  if yt-dlp --write-auto-subs --sub-langs "$lang" --sub-format "srt" --skip-download "$url" >"$temp_log" 2>&1; then
    return 0
  else
    cat "$temp_log"
    return 1
  fi
}

process_srt_to_text() {
  local srt_file="$1"
  local video_title="$2"
  local output_file
  output_file=$(create_temp_file "$(date +"%Y%m%d_%H%M%S")-transcript.txt")

  awk '
        !/^[0-9]+$/ && 
        !/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ && 
        !/^$/ {
            gsub(/^[ \t]+|[ \t]+$/, "", $0)
            if (length($0) > 0) {
                if (NR > 1 && prev_line !~ /[.!?]$/) {
                    printf " %s", $0
                } else {
                    if (NR > 1) printf "\n"
                    printf "%s", $0
                }
                prev_line = $0
            }
        }
        END { if (NR > 0) printf "\n" }
    ' "$srt_file" >"$output_file"

  echo "$output_file"
}

download_and_clean() {
  local url="$1"
  local primary_lang="${2:-$DEFAULT_LANGUAGE}"
  local video_title srt_file output_file use_translation=false
  local primary_lang_name fallback_lang="en"

  # Get language names for display
  primary_lang_name=$(get_language_name "$primary_lang")

  print_info "Starting video processing..."

  start_spinner "Getting video title..."
  video_title=$(get_video_title "$url")
  stop_spinner
  print_info "Video title: $video_title"

  # Change to temp directory for downloads
  cd "$TEMP_DIR"

  # Try primary language first
  if download_with_spinner "Downloading $primary_lang_name transcript..." "$url" "$primary_lang"; then
    if srt_file=$(validate_subtitle_content "$primary_lang"); then
      print_success "$primary_lang_name SRT file found"
      use_translation=false
    else
      srt_file=""
    fi
  else
    die "Failed to download $primary_lang_name transcript"
  fi

  # Fallback to English if primary language is empty or missing (unless primary is already English)
  if [ -z "$srt_file" ] && [ "$primary_lang" != "$fallback_lang" ]; then
    print_warning "No $primary_lang_name content found, trying English..."

    if download_with_spinner "Downloading English transcript..." "$url" "$fallback_lang"; then
      if srt_file=$(validate_subtitle_content "$fallback_lang"); then
        print_success "English SRT file found (will translate to $primary_lang_name)"
        use_translation=true
      else
        die "No English content found either"
      fi
    else
      die "Failed to download English transcript"
    fi
  elif [ -z "$srt_file" ]; then
    die "No subtitles found for this video"
  fi

  # Process SRT to clean text
  output_file=$(process_srt_to_text "$srt_file" "$video_title")
  print_success "Clean transcript saved"

  # Save result for main function
  save_result "$output_file" "$use_translation"
  echo "$output_file"
}

summarize_with_claude() {
  local transcript_file="$1"
  local api_key="$2"
  local use_translation="$3"
  local output_file="$4"
  local target_lang="${5:-$DEFAULT_LANGUAGE}"
  local content summary_file prompt temp_json target_lang_name

  # Get API key
  api_key=$(get_api_key "$api_key")
  [ -z "$api_key" ] && die "No API key provided"

  # Get target language name
  target_lang_name=$(get_language_name "$target_lang")

  print_info "Processing transcript"

  content=$(cat "$transcript_file")

  if [ -n "$output_file" ]; then
    summary_file="$output_file"
  else
    summary_file=$(create_temp_file "summary.txt")
  fi

  if [ "$use_translation" = "true" ]; then
    prompt="First translate the following English transcript to $target_lang_name, then provide a concise $target_lang_name summary of the content, capturing the main points and key information. Do not include the full translation - only provide the summary in $target_lang_name, without any header."
  else
    prompt="Summarize the following $target_lang_name text into a concise summary in $target_lang_name, capturing the main points and key information:"
  fi

  start_spinner "Summarizing with Claude..."

  # Create temporary JSON file to avoid command line length limits
  temp_json=$(create_temp_file "request.json")
  cat >"$temp_json" <<EOF
{
    "model": "$CLAUDE_MODEL",
    "max_tokens": $MAX_TOKENS,
    "messages": [{
        "role": "user",
        "content": "$prompt: \n\n$(printf '%s' "$content" | sed 's/"/\\"/g')"
    }]
}
EOF

  if curl -s -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: $ANTHROPIC_API_VERSION" \
    -d @"$temp_json" | jq -r '.content[0].text' >"$summary_file"; then

    stop_spinner

    if [ -s "$summary_file" ]; then
      if [ -n "$output_file" ]; then
        print_success "Summary saved: $summary_file"
        echo ""
        print_info "Summary preview:"
        printf "${CYAN}%s${NC}\n" "----------------------------------------"
        cat "$summary_file"
        printf "${CYAN}%s${NC}\n" "----------------------------------------"
      else
        echo ""
        print_info "Summary:"
        printf "${CYAN}%s${NC}\n" "----------------------------------------"
        cat "$summary_file"
        printf "${CYAN}%s${NC}\n" "----------------------------------------"
      fi
    else
      die "Failed to generate summary"
    fi
  else
    stop_spinner
    die "Failed to call Claude API"
  fi
}

help() {
  cat <<'EOF'
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
EOF
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

main() {
  OUTPUT_FILE=""
  PRIMARY_LANGUAGE="$DEFAULT_LANGUAGE"

  # Create temporary directory
  TEMP_DIR=$(mktemp -d)
  trap cleanup EXIT

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -l | --language)
        if [ $# -lt 2 ]; then
          echo "Error: -l/--language requires a language code"
          exit 1
        fi
        PRIMARY_LANGUAGE="$2"
        shift 2
        ;;
      -o | --output)
        if [ $# -lt 2 ]; then
          echo "Error: -o/--output requires a file path"
          exit 1
        fi
        OUTPUT_FILE="$2"
        shift 2
        ;;
      -h | --help)
        help
        exit 0
        ;;
      *)
        if [ -z "$URL" ]; then
          URL="$1"
        elif [ -z "$API_KEY" ]; then
          API_KEY="$1"
        fi
        shift
        ;;
    esac
  done

  if [ -z "$URL" ]; then
    help
    exit 1
  fi

  check_dependencies

  # Validate URL
  validate_youtube_url "$URL" || die "Invalid YouTube URL: $URL"

  # Validate output file if specified
  if [ -n "$OUTPUT_FILE" ]; then
    validate_file_path "$OUTPUT_FILE" || die "Cannot write to output file: $OUTPUT_FILE"
  fi

  # Download and clean transcript
  download_and_clean "$URL" "$PRIMARY_LANGUAGE"
  RESULT=$(load_result)
  TRANSCRIPT_FILE=$(echo "$RESULT" | cut -d'|' -f1)
  USE_TRANSLATION=$(echo "$RESULT" | cut -d'|' -f2)

  if [ -f "$TRANSCRIPT_FILE" ]; then
    summarize_with_claude "$TRANSCRIPT_FILE" "$API_KEY" "$USE_TRANSLATION" "$OUTPUT_FILE" "$PRIMARY_LANGUAGE"
  fi
}

main "$@"
