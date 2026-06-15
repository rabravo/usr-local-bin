#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# ab_infosec_cwe.sh — Look up a CWE entry from the official MITRE CWE corpus.
#
# Usage:
#   ./ab_infosec_cwe.sh <CWE-number>
#   ./ab_infosec_cwe.sh 134
#   ./ab_infosec_cwe.sh CWE-134
#   ./ab_infosec_cwe.sh --update     # force re-download of the CWE corpus
#
# Requirements:
#   curl      -- to download the corpus   (apt install curl)
#   python3   -- to parse XML             (usually pre-installed)
#   unzip     -- to unpack the corpus     (apt install unzip)
#
# Source:
#   MITRE CWE corpus (XML)
#   https://cwe.mitre.org/data/xml/cwec_latest.xml.zip
#   Downloaded once and cached in ~/.cache/ab_infosec/cwe/
#   Re-download with: ./ab_infosec_cwe.sh --update
# -----------------------------------------------------------------------------

# ── constants ────────────────────────────────────────────────────────────────
MITRE_URL="https://cwe.mitre.org/data/xml/cwec_latest.xml.zip"
CACHE_DIR="${HOME}/.cache/ab_infosec/cwe"
CACHE_ZIP="${CACHE_DIR}/cwec_latest.xml.zip"
CACHE_XML="${CACHE_DIR}/cwec_latest.xml"

BOLD="\033[1m"
CYAN="\033[36m"
RED="\033[31m"
YELLOW="\033[33m"
GREEN="\033[32m"
RESET="\033[0m"

# ── usage ────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}ab_infosec_cwe.sh${RESET} — Look up a CWE entry from the MITRE CWE corpus."
    echo ""
    echo -e "${BOLD}Usage:${RESET}"
    echo "  $0 <CWE-number>"
    echo "  $0 --update"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo "  $0 134          # accepts plain number"
    echo "  $0 CWE-134      # accepts full CWE ID"
    echo "  $0 --update     # force re-download of the CWE corpus"
    echo ""
    echo -e "${BOLD}Output:${RESET}"
    echo "  ID, name, status, likelihood, description, mitigations."
    echo ""
    echo -e "${BOLD}Requirements:${RESET}"
    echo "  curl, python3, unzip"
    echo ""
    echo -e "${BOLD}Cache:${RESET}"
    echo "  ${CACHE_DIR}"
    echo ""
    exit 1
}

# ── helpers ──────────────────────────────────────────────────────────────────
check_dependencies() {
    local missing=0
    for cmd in curl python3 unzip; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}Error:${RESET} '$cmd' is required but not installed."
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && exit 1
}

# strip optional "CWE-" prefix so both "134" and "CWE-134" work
normalise_id() {
    echo "${1^^}" | sed 's/^CWE-//'
}

download_corpus() {
    echo -e "${CYAN}Downloading MITRE CWE corpus...${RESET}"
    mkdir -p "$CACHE_DIR"
    if ! curl -s --max-time 30 "$MITRE_URL" -o "$CACHE_ZIP"; then
        echo -e "${RED}Error:${RESET} Failed to download CWE corpus. Check your network connection."
        exit 1
    fi
    echo -e "${CYAN}Unpacking...${RESET}"
    unzip -o "$CACHE_ZIP" -d "$CACHE_DIR" > /dev/null
    # rename whatever xml file was extracted to a stable name
    find "$CACHE_DIR" -name "cwec_v*.xml" | head -1 | xargs -I{} mv {} "$CACHE_XML"
    echo -e "${GREEN}Corpus cached at:${RESET} ${CACHE_DIR}"
    echo ""
}

# ── argument check ───────────────────────────────────────────────────────────
if [ "$#" -ne 1 ] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

check_dependencies

# handle --update flag
if [[ "$1" == "--update" ]]; then
    download_corpus
    echo -e "${GREEN}Done.${RESET} CWE corpus updated."
    exit 0
fi

CWE_NUM=$(normalise_id "$1")

# basic validation — must be a number
if ! [[ "$CWE_NUM" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error:${RESET} '$1' is not a valid CWE number."
    usage
fi

CWE_ID="CWE-${CWE_NUM}"

# ── ensure corpus is cached ───────────────────────────────────────────────────
if [ ! -f "$CACHE_XML" ]; then
    echo -e "${YELLOW}CWE corpus not found in cache.${RESET}"
    download_corpus
fi

# ── parse and display ─────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}Looking up ${BOLD}${CWE_ID}${RESET}${CYAN} in local corpus...${RESET}"
echo ""

python3 - "$CWE_NUM" "$CACHE_XML" <<'PYEOF'
import sys, xml.etree.ElementTree as ET, textwrap

cwe_num  = sys.argv[1]
xml_path = sys.argv[2]

BOLD   = "\033[1m"
CYAN   = "\033[36m"
RED    = "\033[31m"
YELLOW = "\033[33m"
GREEN  = "\033[32m"
RESET  = "\033[0m"
SEP    = "─" * 60
NS     = "http://cwe.mitre.org/cwe-7"

def tag(name):
    return f"{{{NS}}}{name}"

def get_text(el, child_tag):
    child = el.find(tag(child_tag))
    return child.text.strip() if child is not None and child.text else ""

def wrap(text, width=70):
    return "\n".join("  " + l for l in textwrap.wrap(text, width))

tree = ET.parse(xml_path)
root = tree.getroot()

weakness = None
for w in root.iter(tag("Weakness")):
    if w.get("ID") == cwe_num:
        weakness = w
        break

if weakness is None:
    print(f"{RED}No entry found for CWE-{cwe_num}.{RESET}")
    print(f"Check: https://cwe.mitre.org/data/definitions/{cwe_num}.html")
    sys.exit(0)

print(f"{BOLD}{SEP}{RESET}")
print(f"{BOLD}ID:          {RESET}{CYAN}CWE-{weakness.get('ID')}{RESET}")
print(f"{BOLD}Name:        {RESET}{weakness.get('Name', 'N/A')}")
print(f"{BOLD}Abstraction: {RESET}{weakness.get('Abstraction', 'N/A')}")
print(f"{BOLD}Status:      {RESET}{YELLOW}{weakness.get('Status', 'N/A')}{RESET}")

likelihood = get_text(weakness, "Likelihood_Of_Exploit")
if likelihood:
    color = RED if likelihood.lower() == "high" else YELLOW
    print(f"{BOLD}Likelihood:  {RESET}{color}{likelihood}{RESET}")

desc = get_text(weakness, "Description")
if desc:
    print(f"\n{BOLD}Description:{RESET}")
    print(wrap(desc))

# Mitigations
mit_el = weakness.find(tag("Potential_Mitigations"))
if mit_el is not None:
    mitigations = []
    for m in mit_el.findall(tag("Mitigation")):
        desc_el = m.find(tag("Description"))
        if desc_el is not None and desc_el.text:
            mitigations.append(desc_el.text.strip())
    if mitigations:
        print(f"\n{BOLD}Mitigations:{RESET}")
        for i, m in enumerate(mitigations[:3], 1):
            print(f"  {i}. {textwrap.fill(m, width=68, subsequent_indent='     ')}")

# Related weaknesses
rel_el = weakness.find(tag("Related_Weaknesses"))
if rel_el is not None:
    parents = [r.get("CWE_ID") for r in rel_el.findall(tag("Related_Weakness"))
               if r.get("Nature") == "ChildOf"]
    if parents:
        print(f"\n{BOLD}Parent CWEs: {RESET}{', '.join('CWE-'+p for p in parents)}")

print(f"\n{BOLD}{SEP}{RESET}")
PYEOF

echo -e "${GREEN}Reference:${RESET} https://cwe.mitre.org/data/definitions/${CWE_NUM}.html"
echo ""
