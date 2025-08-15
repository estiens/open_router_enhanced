# Security Policy

## Supported Versions

We release patches for security vulnerabilities for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take the security of OpenRouter Enhanced seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### Where to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to:

- **Email**: opensource@ericstiens.dev (replace with actual contact)
- **Subject Line**: `[SECURITY] OpenRouter Enhanced - Brief Description`

Alternatively, you can use GitHub's private vulnerability reporting feature:

1. Go to the repository's Security tab
2. Click "Report a vulnerability"
3. Fill out the form with details

### What to Include

Please include the following information in your report:

- Type of issue
- Full paths of source file(s) related to the issue
- Location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### What to Expect

After you submit a report:

1. **Acknowledgment**: We will acknowledge receipt of your vulnerability report within 48 hours.

2. **Initial Assessment**: We will perform an initial assessment and respond with our evaluation within 5 business days.

3. **Updates**: We will keep you informed about our progress towards resolving the issue.

4. **Resolution**: Once the issue is resolved, we will:
   - Release a security patch
   - Publicly disclose the vulnerability (with credit to you, if desired)
   - Add the issue to our security advisories

### Disclosure Policy

- We ask that you do not publicly disclose the vulnerability until we have had a chance to address it.
- We will coordinate with you on the disclosure timeline.
- We aim to resolve critical issues within 30 days of acknowledgment.

## Security Best Practices for Users

When using the OpenRouter Enhanced gem:

1. **API Keys**:
   - Never hardcode API keys in your code
   - Use environment variables or secure credential storage
   - Rotate API keys regularly
   - Never commit API keys to version control

2. **Dependency Management**:
   - Keep the gem updated to the latest version
   - Regularly run `bundle update` to get security patches
   - Monitor security advisories for dependencies

3. **Input Validation**:
   - Validate all user inputs before passing to the gem
   - Be cautious with tool calling and structured outputs from untrusted sources
   - Sanitize data before execution

4. **Network Security**:
   - Use HTTPS for all API communications (enabled by default)
   - Verify SSL certificates (enabled by default)
   - Be cautious with proxy configurations

5. **Error Handling**:
   - Avoid exposing detailed error messages to end users
   - Log errors securely without exposing sensitive data
   - Monitor for unusual error patterns

## Known Security Considerations

### API Key Storage

The gem requires an OpenRouter API key for operation. Users are responsible for:
- Securely storing their API keys
- Not committing keys to version control
- Using environment variables or secure vaults

### Tool Calling

When using tool calling features:
- Validate tool arguments before execution
- Implement proper authorization checks
- Sandbox tool execution where appropriate
- Never execute arbitrary code from LLM responses without validation

### Data Privacy

When using the gem:
- Be aware that data is sent to OpenRouter's API
- Review OpenRouter's privacy policy and terms of service
- Implement appropriate data handling for sensitive information
- Consider data residency requirements for your use case

## Security Update Process

1. Security issues are prioritized based on severity and impact
2. Patches are developed and tested in private
3. Security advisories are prepared
4. Patches are released via a new gem version
5. Security advisories are published
6. Users are notified through:
   - GitHub Security Advisories
   - RubyGems security notifications
   - Project changelog
   - Release notes

## Bug Bounty Program

We currently do not have a bug bounty program. However, we greatly appreciate security researchers who responsibly disclose vulnerabilities and will publicly acknowledge their contributions (with permission).

## Contact

For general security questions or concerns, please use the same contact methods as vulnerability reporting.

For non-security-related issues, please use the standard GitHub issues process.

## Acknowledgments

We would like to thank the following individuals for responsibly disclosing security issues:

(This section will be updated as security issues are responsibly disclosed and resolved)

---

Last updated: 2025-10-05
