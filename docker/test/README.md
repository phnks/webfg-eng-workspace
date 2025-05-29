# Docker Test Scripts

This directory contains test scripts for the Docker setup.

## Available Tests

- `test-docker-setup.sh` - Basic Docker setup validation
- `test-full-setup.sh` - Complete end-to-end test including agent startup
- `test-working-setup.sh` - Test a working agent configuration
- `run-tests.sh` - Run all tests

## Usage

```bash
# Run all tests
./run-tests.sh

# Run specific test
./test-docker-setup.sh
```

## Test Environment

The `.env.test` file contains test environment variables. Do not use these in production.