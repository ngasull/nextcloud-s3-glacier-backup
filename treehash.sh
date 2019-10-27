#!/bin/bash

# This file is borrowed from https://github.com/numblr/glaciertools/blob/master/treehash
# Special thanks to Thomas Baier!

set -e

########
# Constants
########

readonly NL=$'\n'
readonly TAB=$'\t'


########
# Parse command line options
########

function print_usage {
  echo "usage: treehash [-b|--block <size>] [-a|--alg <alg>] [-v|--verbosity <level>] <file>"
  echo ""
  echo "Calculates the top level hash of a Merkel tree (tree hash) built from equal sized chunks of a file."
  echo ""
  echo "    --block      size of the leaf data blocks in bytes, defaults to 1M."
  echo "                 can be postfixed with K, M, G, T, P, E, k, m, g, t, p, or e,"
  echo "                 see the '--block' option of the 'parallel' command for details."
  echo "    --alg        hash algorithm to use, defaults to 'sha256'. Supported"
  echo "                 algorithms are the ones supported by 'openssl dgst'"
  echo "    --verbosity  print diagnostic messages to stderr if level is larger than 0:"
  echo "                   * level 1: Print the entire tree"
  echo "                   * level 2: Print debug information"
}

arg_positional=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
      -h|--help)
      print_usage
      exit 0
      ;;
      -b|--block)
      arg_block="$2"
      shift # past argument
      shift # past value
      ;;
      -v|--verbosity)
      arg_log="$2"
      shift # past argument
      shift # past value
      ;;
      -a|--alg)
      arg_alg="$2"
      shift # past argument
      shift # past value
      ;;
      *)    # unknown option
      arg_positional+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done
set -- "${arg_positional[@]}" # restore positional parameters

if [[ -n "$arg_log" ]] && ! [[ "$arg_log" -eq "$arg_log" ]] 2> /dev/null
then
    echo "verbosity level must be an integer!"
    echo ""
    print_usage
    exit 1
fi

readonly log=${arg_log:-0}
readonly block_size="${arg_block:-1M}"
readonly hash_alg="${arg_alg:-sha256}"


##########
# Utility functions
##########

function combine_hash {
  # Concat, convert hex format to binary and hash
  echo -n "$1$2" | xxd -r -p | openssl dgst -"$hash_alg" -hex | cut -f 2 -d ' '
}

function indent {
  depth=$(($1*4))
  eval ">&2 printf ' %.0s' {1..$depth}"
}

############
# Calculate tree hash iterating stdin
############

function calculate_root_hash {
  local left right max_depth
  max_depth="$1"

  # Base case: read chunk from stdin and calculate leaf hash
  if (( max_depth == 0 )); then
    local hash
    read -r hash && hash="${hash##* }"
    if [[ -z "$hash" ]]; then
      ((log > 1)) && >&2 echo "Input exhausted" || :
      exit 0
    fi

    ((log > 1)) && >&2 echo "Read $hash" || :
    echo -n "$hash"
    exit 0
  fi

  # Recurse to calculate left/right child hashes and combine them
  left=$(calculate_root_hash $((max_depth - 1)))
  if [[ -z "$left" ]]; then
    ((log > 1)) && >&2 echo "Terminate: no left root"|| :
    exit 0
  fi
  ((log > 0)) && indent $max_depth && >&2 echo "left ($((max_depth-1))): $left" || :

  right=$(calculate_root_hash $((max_depth - 1)))
  if [[ -z "$right" ]]; then
    ((log > 1)) && >&2 echo "Terminate: no right root" || :
    echo -n "$left"
    exit 0
  fi
  ((log > 0)) && indent $max_depth && >&2 echo "right ($((max_depth-1))): $right" || :

  combine_hash "$left" "$right"
}

function calculate_hash {
  local left right level
  left="$1"
  level="$2"

  # Initialize
  if [[ -z "$left" ]]; then
    local first
    first="$(calculate_root_hash 0)"
    if [[ -z "$first" ]]; then
      ((log > 1)) && >&2 echo "No input" || :
      exit 0
    fi

    ((log > 1)) && >&2 echo "Initialize with $first" || :
    calculate_hash "$first" 0
    exit 0
  fi

  ((log > 1)) && >&2 echo "Calculate hash at level $level" || :
  ((log > 0)) && indent $((level+1)) && >&2 echo "Left ($level): $left" || :

  # Calculate right child and recurse to calculate the next level
  right=$(calculate_root_hash $level)
  if [[ -z "$right" ]]; then
    ((log > 1)) && >&2 echo "Terminate: no right child, return left: $left" || :
    echo -n "$left"
    exit 0
  fi

  ((log > 0)) && indent $((level+1)) && >&2 echo "Right ($level): $right" || :

  combined=$(combine_hash "$left" "$right")
  ((log > 1)) && indent $((level+1)) && >&2 echo "Combined hash ($level): $combined" || :

  calculate_hash "$combined" $((level + 1))
}


########
# Split stdin into chunks and feed into the hash algorithm
########

input_file="$1"

((log > 0)) && >&2 echo "Calculate hash for $input_file" || :

cat "$input_file" \
  | parallel --no-notice --pipe --block "$block_size" --recend '' -k \
      "openssl dgst -$hash_alg -hex" \
  | calculate_hash "" 0

# Terminate with newline
echo ""
