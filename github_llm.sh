#!/usr/bin/env bash
set -euo pipefail

# ---------- Utility Functions ----------

usage() {
  cat <<EOF
Usage:
  $0 [-l | -f <file> | -d <dir> | --rate <model>] <prompt> <model> <token>
  $0 token

Options:
  -l, --list-models         List all available models (requires <token> only)
  -f <file>                 Include one file as context
  -d <dir>                  Include all files under <dir> as context
  --rate <model>            Show rate limit tier and documented limits for a model

Positional:
  <prompt>                  Your user prompt (quote if multi-word)
  <model>                   Model ID, e.g. openai/gpt-4o
  <token>                   GitHub PAT with models:read

Examples:
  $0 -l ghp_...
  $0 "Explain recursion" openai/gpt-4o ghp_...
  $0 -f src/app.js "Refactor this" openai/gpt-4o ghp_...
  $0 -d src "Summarize module" openai/gpt-4o ghp_...
  $0 --rate openai/gpt-4o ghp_...
  $0 token
EOF
  exit 1
}

show_token_help() {
  cat <<EOF
How to get a GitHub token for the Models API:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" (choose "Fine-grained token" if available).
3. Give your token a descriptive name and (optionally) set an expiration.
4. Under "Resource owner," select your user or organization.
5. Under "Repository access," select "All repositories" or limit as needed.
6. Under "Permissions," add:
     - models:read
7. Click "Generate token" and copy the value (it will only be shown once).
8. Use this token as the last argument to this script.

For more details, see:
https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models

TIP: Never share your token publicly. Treat it like a password.
EOF
  exit 0
}

require_jq() {
  command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
}

# ---------- Model and Rate Limit Functions ----------

list_models() {
  local token="$1"
  get_models "$token" | jq
  exit 0
}

get_models() {
  local token="$1"
  curl -sSL \
       -H "Accept: application/vnd.github+json" \
       -H "Authorization: Bearer $token" \
       -H "X-GitHub-Api-Version: 2022-11-28" \
       https://models.github.ai/catalog/models
}

get_model_rate_tier() {
  local model="$1"
  local token="$2"
  get_models "$token" | \
    jq -r --arg model "$model" '
      .[] | select(.id == $model) | .rate_limit_tier // empty
    '
}

show_rate_limits_for_tier() {
  local tier="$1"
  case "$tier" in
    (Low|low)
      cat <<EOF
Low Tier:
- Requests per minute: 15 (Free/Pro/Business), 20 (Enterprise)
- Requests per day: 150 (Free/Pro), 300 (Business), 450 (Enterprise)
- Tokens per request: 8000 in, 4000 out (Free/Pro/Business), 8000 in, 8000 out (Enterprise)
- Concurrent requests: 5 (Free/Pro/Business), 8 (Enterprise)
EOF
      ;;
    (High|high)
      cat <<EOF
High Tier:
- Requests per minute: 10 (Free/Pro/Business), 15 (Enterprise)
- Requests per day: 50 (Free/Pro), 100 (Business), 150 (Enterprise)
- Tokens per request: 8000 in, 4000 out (Free/Pro/Business), 16000 in, 8000 out (Enterprise)
- Concurrent requests: 2 (Free/Pro/Business), 4 (Enterprise)
EOF
      ;;
    (Embedding|embedding)
      cat <<EOF
Embedding Tier:
- Requests per minute: 15 (Free/Pro/Business), 20 (Enterprise)
- Requests per day: 150 (Free/Pro), 300 (Business), 450 (Enterprise)
- Tokens per request: 64000
- Concurrent requests: 5 (Free/Pro/Business), 8 (Enterprise)
EOF
      ;;
    (*)
      echo "Unknown or missing rate tier: $tier"
      ;;
  esac
}

show_model_limits() {
  local model="$1"
  local token="$2"
  local tier
  tier=$(get_model_rate_tier "$model" "$token")
  if [[ -z "$tier" ]]; then
    echo "Model not found or no rate tier info available."
    return 1
  fi
  echo "Model: $model"
  echo "Rate tier: $tier"
  show_rate_limits_for_tier "$tier"
}

check_rest_api_rate_usage() {
  local token="$1"
  curl -sSL -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/rate_limit" | jq '.resources.core'
}

# ---------- File Handling Functions ----------

# function that retunrns file content as string not json!
build_files_json_from_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "File not found: $file"
        exit 1
    fi
    # converts fileconent to string
    local content
    content=$(jq -Rs . < "$file")
    echo "$content"
}

build_files_json_from_dir() {
  local dir="$1"
  local entries=()
  while IFS= read -r -d '' f; do
    rel="${f#$dir/}"
    entries+=("$(jq -n \
      --arg path "$rel" \
      --rawfile content "$f" \
      '{path:$path, content:$content, encoding:"utf-8"}')")
  done < <(find "$dir" -type f -print0)
  printf "%s\n" "${entries[@]}" | jq -s '.'
}

build_payload() {
  local model="$1"
  local prompt="$2"
  local files_json="$3"
  local token_limit="1000"
  if [ -n "$files_json" ]; then
    jq -n \
      --arg model "$model" \
      --arg prompt "$prompt" \
      --arg token_limit "$token_limit" \
      --arg files "$files_json" \
      '{
        messages: [{
            role: "user", 
            content: [
                {text: $prompt, type: "text"},
                {text: $files, type: "text"}
            ],
        }],
        max_tokens: ($token_limit | tonumber),
        temperature: 1.0,
        top_p: 1.0,
        stream: false,       
        model: $model,
      }'
  else
    jq -n \
      --arg model "$model" \
      --arg prompt "$prompt" \
      --arg token_limit "$token_limit" \
      '{
        messages: [{
            role: "user", 
            content: $prompt,
        }],
        max_tokens: ($token_limit | tonumber),
        temperature: 1.0,
        top_p: 1.0,
        stream: false,       
        model: $model,
      }'
  fi
}

call_github_api() {
  local payload="$1"
  local token="$2"
  curl -sSL -X POST "https://models.github.ai/inference/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "$payload"
}

print_model_response() {
  local response_json="$1"
  # Extract main fields using jq
  local message finish_reason completion_tokens prompt_tokens total_tokens
  message=$(echo "$response_json" | jq -r '.choices[0].message.content // "No response."')
  finish_reason=$(echo "$response_json" | jq -r '.choices[0].finish_reason // "unknown"')
  completion_tokens=$(echo "$response_json" | jq -r '.usage.completion_tokens // "N/A"')
  prompt_tokens=$(echo "$response_json" | jq -r '.usage.prompt_tokens // "N/A"')
  total_tokens=$(echo "$response_json" | jq -r '.usage.total_tokens // "N/A"')

  echo -e "Assistant's message:\n$message\n"
  echo "Finish reason: $finish_reason"
  echo
  echo "Token usage:"
  echo "  Completion tokens: $completion_tokens"
  echo "  Prompt tokens:     $prompt_tokens"
  echo "  Total tokens:      $total_tokens"
  echo
}


# ---------- Main Argument Parsing ----------

require_jq

if [[ $# -eq 1 && "$1" == "token" ]]; then
  show_token_help
fi

file=""
dir=""
list_models_flag=0
rate_flag=0
rate_model=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    (-f)
      file="$2"
      shift 2
      ;;
    (-d)
      dir="$2"
      shift 2
      ;;
    (-l|--list-models)
      list_models_flag=1
      shift
      ;;
    (--rate)
      rate_flag=1
      rate_model="$2"
      shift 2
      ;;
    (-*)
      usage
      ;;
    (*)
      break
      ;;
  esac
done

if [[ $list_models_flag -eq 1 ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Token required for listing models."
    usage
  fi
  list_models "$1"
fi

if [[ $rate_flag -eq 1 ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Token required for showing rate limits."
    usage
  fi
  show_model_limits "$rate_model" "$1"
  exit 0
fi

if [[ -n "$file" && -n "$dir" ]]; then
  echo "Cannot use both -f and -d at the same time."
  usage
fi

if [[ $# -lt 3 ]]; then
  usage
fi

model="${@: -2:1}"
token="${@: -1}"
argcount=$#
prompt_words=("${@:1:$argcount-2}")
prompt="${prompt_words[*]}"

files_json=""
if [[ -n "$file" ]]; then
  files_json=$(build_files_json_from_file "$file")
elif [[ -n "$dir" ]]; then
  files_json=$(build_files_json_from_dir "$dir")
fi

payload=$(build_payload "$model" "$prompt" "$files_json")
echo "Payload to be sent:"
echo "$payload" | jq
response=""
response=$(call_github_api "$payload" "$token")
echo
echo "Response from the API:"
echo "$response" | jq
echo 
# demo response for testing (reduces API calls)
#response='{"choices":[{"content_filter_results":{"hate":{"filtered":false,"severity":"safe"},"protected_material_code":{"filtered":false,"detected":false},"protected_material_text":{"filtered":false,"detected":false},"self_harm":{"filtered":false,"severity":"safe"},"sexual":{"filtered":false,"severity":"safe"},"violence":{"filtered":false,"severity":"safe"}},"finish_reason":"stop","index":0,"logprobs":null,"message":{"annotations":[],"content":"The capital of France is Paris.","refusal":null,"role":"assistant"}}],"created":1748170943,"id":"chatcmpl-Bb3PTuqhhybwwJR4iAz0CiYUNyr1D","model":"gpt-4o-mini-2024-07-18","object":"chat.completion","prompt_filter_results":[{"prompt_index":0,"content_filter_results":{"hate":{"filtered":false,"severity":"safe"},"jailbreak":{"filtered":false,"detected":false},"self_harm":{"filtered":false,"severity":"safe"},"sexual":{"filtered":false,"severity":"safe"},"violence":{"filtered":false,"severity":"safe"}}}],"system_fingerprint":"fp_7a53abb7a2","usage":{"completion_tokens":8,"completion_tokens_details":{"accepted_prediction_tokens":0,"audio_tokens":0,"reasoning_tokens":0,"rejected_prediction_tokens":0},"prompt_tokens":13,"prompt_tokens_details":{"audio_tokens":0,"cached_tokens":0},"total_tokens":21}}'
print_model_response "$response"