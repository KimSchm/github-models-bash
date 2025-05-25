# github-models-bash

## Project Description

This repository contains a Bash script that interacts with GitHub's Models API. The script provides various functionalities such as listing available models, showing rate limits, and making API calls to generate responses based on user prompts.

## Installation Instructions

To use this script, you need to have `jq` installed. You can install `jq` using the following command:

```bash
sudo apt-get install jq
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

- Show rate limits for a model:

  ```bash
  ./github_llm.sh --rate openai/gpt-4o <token>
  ```

## TO-DO

- Add file support other than raw text
- Add file type detection
- Add checks for if the user has all reqs installed

## Contributing Guidelines

We welcome contributions to this project. Please follow these guidelines when contributing:

1. Fork the repository and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. Ensure the test suite passes.
4. Make sure your code lints.
5. Issue that pull request!

## Code of Conduct

This project adheres to the Contributor Covenant code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to [email@example.com](mailto:email@example.com).

## Badges and Links

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Reporting Issues and Requesting Features

If you encounter any issues or have feature requests, please use the [GitHub Issues](https://github.com/KimSchm/github-models-bash/issues) page to report them.

## Maintainers and Support

This project is maintained by KimSchm.
