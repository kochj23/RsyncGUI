# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.7.x   | Yes       |
| < 1.6   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public GitHub issue**
2. Email: kochj23 (via GitHub)
3. Include: description, steps to reproduce, potential impact

We aim to respond within 48 hours and provide a fix within 7 days for critical issues.

## Security Features

- **Shell Command Escaping**: All rsync arguments properly escaped to prevent injection
- **Plist Injection Prevention**: Schedule/job plist values validated against injection
- **Input Length Limits**: Path and hostname inputs capped to prevent buffer abuse
- **Hostname Validation**: RFC-compliant regex validation for all hostnames
- **Keychain Storage**: Cloud AI API keys stored in macOS Keychain
- **Thread Safety**: Job execution state managed with proper synchronization
- **No Sandbox**: App runs without sandbox for full file system access (required for rsync)

## Best Practices

- Never hardcode credentials or SSH keys
- Report suspicious behavior immediately
- Keep dependencies updated
- Review all code changes for security implications
