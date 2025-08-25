#!/bin/sh

# Debian ISO Downloader Script (POSIX Compatible)
# Downloads the latest stable Debian ISO for amd64 architecture

set -e # Exit on any error

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Configuration
ARCH="amd64"
ISO_TYPE="netinst" # Options: netinst, DVD-1, CD-1
BASE_URL="https://cdimage.debian.org/debian-cd/current/${ARCH}/iso-cd"
DOWNLOAD_DIR="${HOME}/Downloads"
VERIFY_CHECKSUM=true
FIND_FASTEST_MIRROR=true

# Known Debian mirrors for speed testing
MIRRORS=(
  "https://cdimage.debian.org/debian-cd/current/${ARCH}/iso-cd"
  "https://mirror.de.leaseweb.net/debian-cd/current/${ARCH}/iso-cd"
  "https://mirror.cs.princeton.edu/pub/mirrors/debian-cd/current/${ARCH}/iso-cd"
  "https://mirrors.edge.kernel.org/debian-cd/current/${ARCH}/iso-cd"
  "https://mirror.fcix.net/debian-cd/current/${ARCH}/iso-cd"
  "https://ftp.acc.umu.se/debian-cd/current/${ARCH}/iso-cd"
)

# Functions
print_info() {
  printf "${CYAN}ℹ${NC} %s\n" "$1"
}

print_success() {
  printf "${GREEN}✓${NC} %s\n" "$1"
}

print_warning() {
  printf "${YELLOW}⚠${NC} %s\n" "$1"
}

print_error() {
  printf "${RED}✗${NC} %s\n" "$1"
}

check_dependencies() {
  for dep in curl wget sha256sum; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      print_error "$dep is required but not installed."
      exit 1
    fi
  done
}

get_latest_iso_name() {
  # Use the fastest mirror to get ISO listing
  mirror_url="${1:-$BASE_URL}"
  
  # Don't print info message here - it interferes with command substitution
  # Get the directory listing and extract ISO filename
  iso_name=$(curl -s "${mirror_url}/" | grep -o "debian-[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*-${ARCH}-${ISO_TYPE}\.iso" | head -1)

  if [ -z "$iso_name" ]; then
    print_error "Could not find latest ISO name" >&2
    exit 1
  fi

  printf "%s" "$iso_name"
}

download_file() {
  url="$1"
  filename="$2"
  filepath="${DOWNLOAD_DIR}/${filename}"
  force_download="$3"  # Optional parameter to force download

  # Check if file already exists
  if [ -f "$filepath" ] && [ "$force_download" != "force" ]; then
    print_warning "File $filename already exists. Skipping download."
    return 0
  fi
  
  # If forcing download, remove existing file
  if [ "$force_download" = "force" ] && [ -f "$filepath" ]; then
    print_info "Re-downloading $filename (checksum failed)..."
    rm -f "$filepath"
  fi

  printf "${PURPLE}📥 ${WHITE}Downloading ${CYAN}%s${WHITE}...${NC}\n" "$filename"
  printf "${GRAY}Source: %s${NC}\n" "$url"
  printf "\n"

  # Download with progress bar
  #if wget --progress=bar:force -O "$filepath" "$url"; then
  if wget -nv --show-progress --progress=bar:force -O "$filepath" "$url"; then
    printf "\n"
    print_success "Downloaded $filename"
    return 0
  else
    print_error "Failed to download $filename"
    rm -f "$filepath" # Remove partial download
    return 1
  fi
}

verify_checksum() {
  iso_file="$1"
  checksum_file="${DOWNLOAD_DIR}/SHA256SUMS"

  print_info "Verifying checksum..."

  # Download checksum file
  if ! wget -q -O "$checksum_file" "${BASE_URL}/SHA256SUMS"; then
    print_warning "Could not download checksum file. Skipping verification."
    return 0
  fi

  # Verify checksum
  cd "$DOWNLOAD_DIR" || exit 1

  # Extract the checksum for our specific file
  expected_sum=$(grep "$iso_file" "$checksum_file" | cut -d' ' -f1)
  if [ -z "$expected_sum" ]; then
    print_warning "Checksum not found in SHA256SUMS file"
    rm -f "$checksum_file"
    return 0
  fi

  # Calculate actual checksum
  actual_sum=$(sha256sum "$iso_file" | cut -d' ' -f1)

  if [ "$expected_sum" = "$actual_sum" ]; then
    print_success "Checksum verification passed"
    rm -f "$checksum_file"
    return 0
  else
    print_error "Checksum verification failed"
    print_error "Expected: $expected_sum"
    print_error "Actual:   $actual_sum"
    rm -f "$checksum_file"
    return 1
  fi
}

test_mirror_speed() {
  mirror_url="$1"
  host=$(echo "$mirror_url" | sed 's|https://||' | cut -d'/' -f1)
  
  # Quick single ping test
  ping_time=$(ping -c 1 -W 1000 "$host" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9]*\).*/\1/' 2>/dev/null)
  
  # If ping fails, try curl response time as fallback (faster)
  if [ -z "$ping_time" ] || [ "$ping_time" = "" ]; then
    curl_time=$(curl -s --connect-timeout 1 --max-time 2 -w "%{time_total}" -o /dev/null "$mirror_url" 2>/dev/null)
    if [ -n "$curl_time" ] && [ "$curl_time" != "" ]; then
      # Convert curl time (seconds) to milliseconds
      ping_time=$(awk "BEGIN {printf \"%.0f\", $curl_time * 1000}" 2>/dev/null)
    fi
  fi
  
  # Return ping time or 9999 if failed
  if [ -n "$ping_time" ] && [ "$ping_time" != "" ]; then
    echo "$ping_time"
  else
    echo "9999"
  fi
}

find_fastest_mirror() {
  # Test all mirrors and find the fastest one
  FASTEST_MIRROR=""
  best_time=9999
  
  printf "${CYAN}Testing mirror speeds...${NC}\n"
  printf "\n"
  
  for mirror in "${MIRRORS[@]}"; do
    host=$(echo "$mirror" | sed 's|https://||' | cut -d'/' -f1)
    printf "${GRAY}%-35s${NC} " "$host"
    
    ping_time=$(test_mirror_speed "$mirror")
    
    if [ "$ping_time" != "9999" ]; then
      printf "${GREEN}%4d ms${NC}\n" "$ping_time"
      
      # Check if this is the best time so far
      if [ "$ping_time" -lt "$best_time" ]; then
        best_time="$ping_time"
        FASTEST_MIRROR="$mirror"
      fi
    else
      printf "${RED}Failed${NC}\n"
    fi
  done
  
  if [ -n "$FASTEST_MIRROR" ]; then
    printf "\n"
    fastest_host=$(echo "$FASTEST_MIRROR" | sed 's|https://||' | cut -d'/' -f1)
    print_success "Fastest mirror: $fastest_host (${best_time}ms)"
  else
    printf "\n"
    print_warning "All mirrors failed, using default"
    FASTEST_MIRROR="$BASE_URL"
  fi
}

get_file_size() {
  file="$1"
  if command -v du >/dev/null 2>&1; then
    du -h "$file" | cut -f1
  else
    # Fallback using ls
    ls -lh "$file" | awk '{print $5}'
  fi
}

show_usage() {
  cat <<'EOF'
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

EOF
}

# Parse command line arguments
while [ $# -gt 0 ]; do
  case $1 in
  -t)
    if [ -z "$2" ]; then
      print_error "Option -t requires an argument"
      exit 1
    fi
    ISO_TYPE="$2"
    shift 2
    ;;
  -d)
    if [ -z "$2" ]; then
      print_error "Option -d requires an argument"
      exit 1
    fi
    DOWNLOAD_DIR="$2"
    shift 2
    ;;
  -s)
    VERIFY_CHECKSUM=false
    shift
    ;;
  -m)
    FIND_FASTEST_MIRROR=false
    shift
    ;;
  -h)
    show_usage
    exit 0
    ;;
  *)
    print_error "Unknown option: $1"
    show_usage
    exit 1
    ;;
  esac
done

# Validate ISO type
case $ISO_TYPE in
netinst | DVD-1 | CD-1) ;;
*)
  print_error "Invalid ISO type: $ISO_TYPE"
  print_info "Valid types: netinst, DVD-1, CD-1"
  exit 1
  ;;
esac

# Main execution
main() {
  print_info "Debian ISO Downloader"
  print_info "Architecture: $ARCH"
  print_info "ISO Type: $ISO_TYPE"
  print_info "Download Directory: $DOWNLOAD_DIR"
  printf "\n"

  # Check dependencies
  check_dependencies

  # Create download directory if it doesn't exist
  mkdir -p "$DOWNLOAD_DIR"

  # Get latest ISO name first (using default mirror for quick lookup)
  print_info "Fetching latest ISO information..."
  ISO_NAME=$(get_latest_iso_name "$BASE_URL")
  print_info "Latest ISO: $ISO_NAME"
  
  # Check if file already exists and is valid
  if [ -f "${DOWNLOAD_DIR}/${ISO_NAME}" ]; then
    if [ "$VERIFY_CHECKSUM" = true ]; then
      print_info "File exists, verifying checksum..."
      if verify_checksum "$ISO_NAME"; then
        print_success "File already exists and checksum is valid!"
        
        # Show file info and exit successfully
        printf "\n"
        print_info "File location: ${DOWNLOAD_DIR}/${ISO_NAME}"
        file_size=$(get_file_size "${DOWNLOAD_DIR}/${ISO_NAME}")
        print_info "File size: $file_size"
        return 0
      else
        print_warning "Existing file has invalid checksum, will re-download"
      fi
    else
      print_success "File already exists!"
      
      # Show file info and exit successfully  
      printf "\n"
      print_info "File location: ${DOWNLOAD_DIR}/${ISO_NAME}"
      file_size=$(get_file_size "${DOWNLOAD_DIR}/${ISO_NAME}")
      print_info "File size: $file_size"
      return 0
    fi
  fi

  # File doesn't exist or is invalid, find fastest mirror for download
  if [ "$FIND_FASTEST_MIRROR" = true ]; then
    print_info "Testing mirrors for fastest connection..."
    find_fastest_mirror
    # FASTEST_MIRROR is set by the function
    if [ -z "$FASTEST_MIRROR" ]; then
      print_warning "Mirror selection failed, using default"
      FASTEST_MIRROR="$BASE_URL"
    fi
  else
    print_info "Using default mirror"
    FASTEST_MIRROR="$BASE_URL"
  fi
  
  printf "\n"

  # Construct download URL using fastest mirror
  ISO_URL="${FASTEST_MIRROR}/${ISO_NAME}"

  # Download ISO (with retry on checksum failure)
  download_attempt=0
  max_attempts=2
  download_success=false
  
  while [ $download_attempt -lt $max_attempts ]; do
    force_param=""
    if [ $download_attempt -gt 0 ]; then
      force_param="force"
    fi
    
    if download_file "$ISO_URL" "$ISO_NAME" "$force_param"; then
      # Verify checksum if requested
      if [ "$VERIFY_CHECKSUM" = true ]; then
        if verify_checksum "$ISO_NAME"; then
          print_success "ISO downloaded and verified successfully!"
          download_success=true
          break
        else
          download_attempt=$((download_attempt + 1))
          if [ $download_attempt -lt $max_attempts ]; then
            print_warning "Checksum verification failed. Retrying download..."
            printf "\n"
          else
            print_error "Checksum verification failed after $max_attempts attempts."
            exit 1
          fi
        fi
      else
        print_success "ISO downloaded successfully!"
        download_success=true
        break
      fi
    else
      print_error "Failed to download ISO"
      exit 1
    fi
  done
  
  if [ "$download_success" = true ]; then
    # Show file info
    printf "\n"
    print_info "File location: ${DOWNLOAD_DIR}/${ISO_NAME}"
    file_size=$(get_file_size "${DOWNLOAD_DIR}/${ISO_NAME}")
    print_info "File size: $file_size"

    # Show next steps
    printf "\n"
    print_info "Next steps:"
    printf "  1. Verify the download: sha256sum %s/%s\n" "$DOWNLOAD_DIR" "$ISO_NAME"
    printf "  2. Create bootable USB: dd if=%s/%s of=/dev/sdX bs=4M status=progress\n" "$DOWNLOAD_DIR" "$ISO_NAME"
    printf "  3. Or burn to DVD using your preferred burning software\n"
  fi
}

# Run main function
main "$@"
