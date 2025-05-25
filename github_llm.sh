#!/usr/bin/env bash
set -euo pipefail   # Exit on error, undefined variable, or failed pipe
list_models_flag=0
rate_flag=0
recursive_flag=0

# ---------- Utility Functions ----------

# Displays usage information
usage() {
    printf "Usage:\n"
    printf "  %s [-l | -f <file> | -d <dir> | -r <dir> | --rate <model>] <prompt> <model> <token>\n" "$0"
    printf "\nOptions:\n"
    printf "  -l, --list-models         List all available models (requires <token> only)\n"
    printf "  -f <file>                 Include one file as context\n"
    printf "  -d <dir>                  Include all files under <dir> as context\n"
    printf "  -r <dir>                  Include all files under <dir> and its recursive dir's as context\n"
    printf "  --rate <model>            Show rate limit tier and documented limits for a model\n\n"
    printf "Positional Arguments:\n"
    printf "  <prompt>                  Your user prompt (quote if multi-word)\n"
    printf "  <model>                   Model ID, e.g., openai/gpt-4o\n"
    printf "  <token>                   GitHub PAT with models:read permission\n\n"
    printf "Examples:\n"
    printf "  %s -l <token>\n" "$0"
    printf "      List all available models using the provided token.\n\n"
    printf "  %s \"Explain recursion\" openai/gpt-4o <token>\n" "$0"
    printf "      Send a prompt to the specified model.\n\n"
    printf "  %s -f src/app.js \"Refactor this code\" openai/gpt-4o <token>\n" "$0"
    printf "      Include a single file as context for the prompt.\n\n"
    printf "  %s -d src \"Summarize the module\" openai/gpt-4o <token>\n" "$0"
    printf "      Include all files in the specified directory as context.\n\n"
    printf "  %s -r src \"Summarize the module recursively\" openai/gpt-4o <token>\n" "$0"
    printf "      Include all files in the directory and its subdirectories as context.\n\n"
    printf "  %s --rate openai/gpt-4o <token>\n" "$0"
    printf "      Show the rate limit tier and documented limits for the specified model.\n\n"
    printf "  %s token\n" "$0"
    printf "      Show instructions for generating a GitHub token.\n\n"
    printf "Notes:\n"
    printf "  - Always ensure your token has the 'models:read' permission.\n"
    printf "  - Only use -r or -d to enable recursive directory traversal.\n"
    printf "  - For multi-word prompts, enclose them in quotes.\n\n"
    exit 1
}
# Shows how to get a GitHub token for the Models API
show_token_help() {
    printf "How to get a GitHub token for the Models API:\n\n"
    printf "1. Go to https://github.com/settings/tokens \n"
    printf "2. Click \"Generate new token\" (choose \"Fine-grained token\" if available).\n"
    printf "3. Give your token a descriptive name and (optionally) set an expiration.\n"
    printf "4. Under \"Resource owner,\" select your user or organization.\n"
    printf "5. Under \"Repository access,\" select \"All repositories\" or limit as needed.\n"
    printf "6. Under \"Permissions,\" add:\n"
    printf "    - models:read\n"
    printf "7. Click \"Generate token\" and copy the value (it will only be shown once).\n"
    printf "8. Use this token as the last argument to this script.\n"
    printf "\nFor more details, see:\n"
    printf "https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models\n"
    printf "\nTIP: Never share your token publicly. Treat it like a password.\n"
    exit 0
}
# Checks if jq is installed
require_jq() {
    command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
}
# Checks if the 'file' command is installed
require_file() {
    command -v file >/dev/null 2>&1 || { echo "file is required but not installed."; exit 1; }
}
# Checks if pdftotext is installed
require_pdftotext() {
    command -v pdftotext >/dev/null 2>&1 || { echo "pdftotext is required but not installed."; exit 1; }
}
# Detects the MIME type of a file
# Output: MIME type string, e.g. "text/plain", "image/jpeg", etc.
detect_file_type() {
    local file="$1"
    file --mime-type -b "$file"
}


# ---------- Model and Rate Limit Functions ----------

# Lists all available models from GitHub Models API
list_models() {
    local token="$1"
    get_models "$token" | jq
    exit 0
}
# Gets the list of available models from GitHub Models API
get_models() {
    local token="$1"
    curl -sSL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        https://models.github.ai/catalog/models
}
# Gets the rate tier for a specific model
get_model_rate_tier() {
    local model="$1"
    local token="$2"
    get_models "$token" | jq -r --arg model "$model" \
        '.[] | select(.id == $model) | .rate_limit_tier // empty'
}
# Shows the rate limits for a specific tier
show_rate_limits_for_tier() {
    local tier="$1"
    case "$tier" in
        (Low|low)
            printf "\nLow Tier:\n"
            printf "  - Requests per minute: 15 (Free/Pro/Business), 20 (Enterprise)\n"
            printf "  - Requests per day: 150 (Free/Pro), 300 (Business), 450 (Enterprise)\n"
            printf "  - Tokens per request: 8000 in, 4000 out (Free/Pro/Business), 8000 in, 8000 out (Enterprise)\n"
            printf "  - Concurrent requests: 5 (Free/Pro/Business), 8 (Enterprise)\n"
            ;;
        (High|high)
            printf "\nHigh Tier:\n"
            printf "- Requests per minute: 10 (Free/Pro/Business), 15 (Enterprise)\n"
            printf "- Requests per day: 50 (Free/Pro), 100 (Business), 150 (Enterprise)\n"
            printf "- Tokens per request: 8000 in, 4000 out (Free/Pro/Business), 16000 in, 8000 out (Enterprise)\n"
            printf "- Concurrent requests: 2 (Free/Pro/Business), 4 (Enterprise)\n"
            ;;
        (Embedding|embedding)
            printf "\nEmbedding Tier:\n"
            printf "- Requests per minute: 15 (Free/Pro/Business), 20 (Enterprise)\n"
            printf "- Requests per day: 150 (Free/Pro), 300 (Business), 450 (Enterprise)\n"
            printf "- Tokens per request: 64000\n"
            printf "- Concurrent requests: 5 (Free/Pro/Business), 8 (Enterprise)\n"
            ;;
        (*)
            echo "Unknown or missing rate tier: $tier"
            ;;
    esac
}
# Shows the rate limits and tier for a specific model
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


# ---------- File Conversion Functions ----------

# Converts text files and prompts
# Output: {text: $file_content, type: "text"}
convert_text(){
    local file="$1"
    file_content=$(jq -Rs . < "$file")
    jq -n --arg content "$file_content" '{text: $content, type: "text"}'
}
# Converts image files
# Output: {text: $file_content, type: "text"}
# TODO: CHECK IF WORKING
convert_pdf() {
    local file="$1"
    local content
    content=$(pdftotext "$file" -)
    content=$(jq -Rs . <<< "$content")
    jq -n --arg content "$content" \
        '{text: $content, type: "text"}'
}
# Converts image files
# Output: {"image_url": {"url":"data:image/jpeg;base64,'"${IMAGE_DATA}"'","detail":$detail_level}, "type": "image_url"}
convert_image() {
    local file="$1"
    local detail_level="${2:-low}"
    local image_data
    image_data=$(base64 "$file")
    jq -n --arg url "data:image/jpeg;base64,$image_data" \
        --arg detail "$detail_level" \
        '{image_url: {url: $url, detail: $detail}, type: "image_url"}'
}
# Converts audio files
# Output: {"audio_url": {"url":"data:audio/wav;base64,'"${AUDIO_DATA}"'"},"type": "audio_url"}
# TODO: CHECK IF WORKING
convert_audio() {
    local file="$1"
    local audio_data
    audio_data=$(base64 "$file")
    jq -n --arg url "data:audio/wav;base64,$audio_data" '{audio_url: {url: $url}, type: "audio_url"}'
}
# Converts a single file based on its type
# Output: JSON object with file content or metadata
convert_file() {
    # Check if input is a file and not a directory
    if [[ ! -f "$1" ]]; then
        echo "Input is not a valid file: $1"
        exit 1
    fi
    # Determine the file type and call the appropriate conversion function
    local file="$1"
    local mime_type
    mime_type=$(detect_file_type "$file")
    case "$mime_type" in
        (text/*)
            convert_text "$file"
            ;;
        (application/pdf)
            convert_pdf "$file"
            ;;
        (image/*)
            convert_image "$file"
            ;;
        (audio/*)
            convert_audio "$file"
            ;;
        (*)
            echo "Unsupported file type: $mime_type. Using raw content."
            convert_text "$file"
            ;;
    esac
}
# Converts all files in a directory to JSON format
# Output: JSON array of file contexts
convert_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Directory not found: $dir"
        exit 1
    fi
    local file_contexts="[]"
    local files
    if [[ $recursive_flag -eq 1 ]]; then
        # Find files recursively
        files=$(find "$dir" -type f)
    else
        # Find files non-recursively
        files=$(find "$dir" -maxdepth 1 -type f)
    fi
    for file in $files; do
        if [[ -f "$file" ]]; then
            local file_json
            file_json=$(convert_file "$file")
            file_contexts=$(jq --argjson new_file "$file_json" '. + [$new_file]' <<< "$file_contexts")
        fi
    done
    echo "$file_contexts"
}


# ---------- Main Prompt Handling Functions ----------

# Builds the JSON payload for the API request
build_payload() {
    local model="$1"
    local prompt="$2"
    local token_limit="1000"
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
}
# Builds the JSON payload with file context for the API request
build_payload_context() {
    local model="$1"
    local prompt="$2"
    local file_context="$3"
    local token_limit="1000"
    jq -n \
        --arg model "$model" \
        --arg prompt "$prompt" \
        --arg token_limit "$token_limit" \
        --argjson context "$file_context" \
        '{
            messages: [{
                role: "user", 
                content: (
                    [{text: $prompt, type: "text"}] + $context
                )
            }],
            max_tokens: ($token_limit | tonumber),
            temperature: 1.0,
            top_p: 1.0,
            stream: false,       
            model: $model,
        }'
}
# Calls the GitHub Models API with the given payload and user token
call_github_api() {
    local payload="$1"
    local token="$2"
    curl -sSL -X POST "https://models.github.ai/inference/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$payload"
}
# Prints the model response in a user-friendly format
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
    #echo "Finish reason: $finish_reason\n"
    echo "Token usage:"
    echo "  Completion tokens: $completion_tokens"
    echo "  Prompt tokens:     $prompt_tokens"
    echo "  Total tokens:      $total_tokens"
}
# Main function to handle the prompt and API call
prompt() {
    local prompt="$1"
    local model="$2"
    local file="$3"
    local dir="$4"
    local token="$5"
    local file_context=""
    local payload
    local response=""
    
    # Check if file or directory is provided and convert them to JSON context
    if [[ -n "$file" ]]; then
        file_context=$(convert_file "$file")
    elif [[ -n "$dir" ]]; then
        file_context=$(convert_dir "$dir")
    fi

    # Check if file_context is empty
    if [[ -z "$file_context" ]]; then
        # No files provided, use only prompt
        payload=$(build_payload "$model" "$prompt")
    else
        # Files provided, include them in the payload
        payload=$(build_payload_context "$model" "$prompt" "$file_context")
    fi
    response=$(call_github_api "$payload" "$token")

    #echo "Set variables:"
    #echo "Model: $model"
    #echo "Prompt: $prompt"
    #echo "Files context: $file_context"
    #echo "Payload to be sent:"
    #echo "$payload" | jq
    #echo "Response from the API:"
    #echo "$response" | jq
    print_model_response "$response"
}


# ---------- Main Logic ----------
main(){
    # Check for required commands and tools
    require_jq
    require_file
    require_pdftotext

    # Check if the user requested token help
    if [[ $# -eq 1 && "$1" == "token" ]]; then
        show_token_help
    fi

    local file=""
    local dir=""
    local rate_model=""

    # Parse command-line arguments
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
            (-r)
                recursive_flag=1
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

    # If listing models is requested, ensure a token is provided
    if [[ $list_models_flag -eq 1 ]]; then
        if [[ $# -lt 1 ]]; then
            echo "Token required for listing models."
            usage
        fi
        list_models "$1"
    fi

    # Validate rate limit option
    if [[ $rate_flag -eq 1 ]]; then
        if [[ $# -lt 1 ]]; then
            echo "Token required for showing rate limits."
            usage
        fi
        show_model_limits "$rate_model" "$1"
        exit 0
    fi

    # Validate file and directory options
    if [[ -n "$file" && -n "$dir" ]]; then
        echo "Cannot use both -f and -d at the same time."
        usage
    fi

    # Validate that at least a prompt, model, and token are provided
    if [[ $# -lt 3 ]]; then
        usage
    fi

    # Extract the model and token from the last two arguments
    local model="${@: -2:1}"
    local token="${@: -1}"
    local argcount=$#
    local prompt_words=("${@:1:$argcount-2}")
    local prompt="${prompt_words[*]}"

    # Validate that model and prompt are provided
    if [[ -z "$model" || -z "$prompt" ]]; then
        echo "Model and prompt are required."
        usage
    fi

    # Makes an API call with the provided prompt, model, and token
        if ! prompt "$prompt" "$model" "$file" "$dir" "$token"; then
        echo "Error: API call failed."
        exit 1
    fi
    exit 0   
}

main "$@"
