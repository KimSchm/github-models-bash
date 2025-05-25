# github-models-bash

## Project Description

This repository contains a Bash script that interacts with GitHub's Models API. The script provides various functionalities such as listing available models, showing rate limits, and making API calls to generate responses based on user prompts.

## Installation Instructions

To use this script, you need to have `jq`, `file`, and `pdftotext` installed. You can install them using the following commands:

```bash
sudo apt-get install jq file poppler-utils
```

Clone this repository to your local machine:

```bash
git clone https://github.com/KimSchm/github-models-bash.git
cd github-models-bash
```

Make the script executable:

```bash
chmod +x github_llm.sh
```

## Usage

Here are some examples of how to use the script:

- List all available models:

  ```bash
  ./github_llm.sh -l <token>
  ```

- Generate a response based on a user prompt:

  ```bash
  ./github_llm.sh "Explain recursion" openai/gpt-4o <token>
  ```

- Include a file as context:

  ```bash
  ./github_llm.sh -f src/app.js "Refactor this" openai/gpt-4o <token>
  ```

- Include all files under a directory as context:

  ```bash
  ./github_llm.sh -d src "Summarize module" openai/gpt-4o <token>
  ```

- Include all files under a directory and its subdirectories as context:

  ```bash
  ./github_llm.sh -r src "Summarize module recursively" openai/gpt-4o <token>
  ```

- Show rate limits for a model:

  ```bash
  ./github_llm.sh --rate openai/gpt-4o <token>
  ```

## Supported File Types

The script supports the following file types:

- Text files (e.g., `.txt`, `.md`)
- PDF files (requires `pdftotext`)
- Image files (e.g., `.jpg`, `.png`)
- Audio files (e.g., `.mp3`, `.wav`)

For unsupported file types, the script will use the text option.

## Generating a GitHub Token

To use this script, you need a GitHub Personal Access Token (PAT) with `models:read` permission. Follow these steps to generate one:

1. Go to [GitHub Settings - Tokens](https://github.com/settings/tokens).
2. Click "Generate new token" (choose "Fine-grained token" if available).
3. Give your token a descriptive name and (optionally) set an expiration.
4. Under "Resource owner," select your user or organization.
5. Under "Repository access," select "All repositories" or limit as needed.
6. Under "Permissions," add:
    - `models:read`
7. Click "Generate token" and copy the value (it will only be shown once).
8. Use this token as the last argument to this script.

For more details, see [GitHub Documentation](https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models).

**TIP:** Never share your token publicly. Treat it like a password.

## TO-DO

## Contributing Guidelines

We welcome contributions to this project. Please follow these guidelines when contributing:

1. Fork the repository and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. Ensure the test suite passes.
4. Make sure your code lints.
5. Issue that pull request!

## Code of Conduct

This project adheres to the Contributor Covenant code of conduct. By participating, you are expected to uphold this code.

## Badges and Links

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Reporting Issues and Requesting Features

If you encounter any issues or have feature requests, please use the [GitHub Issues](https://github.com/KimSchm/github-models-bash/issues) page to report them.

## Maintainers and Support

This project is maintained by KimSchm.
