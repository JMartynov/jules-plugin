#!/bin/bash
cat << 'MERGEDIFF' > patch.diff
<<<<<<< SEARCH
        BASE_BRANCH=""
        REPO=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --repo)
                    REPO="$2"
                    shift 2
                    ;;
                *)
                    if [[ -z "$BASE_BRANCH" ]]; then
                        BASE_BRANCH="$1"
                    fi
                    shift
                    ;;
            esac
        done
=======
        BASE_BRANCH=""
        REPO=""
        WAIT=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --repo)
                    REPO="$2"
                    shift 2
                    ;;
                --wait)
                    WAIT=true
                    shift
                    ;;
                *)
                    if [[ -z "$BASE_BRANCH" ]]; then
                        BASE_BRANCH="$1"
                    fi
                    shift
                    ;;
            esac
        done
>>>>>>> REPLACE
MERGEDIFF
