# 1. Use standard Python (Guaranteed Architecture)
FROM python:3.11-slim

WORKDIR /app

# 2. Install LiteLLM
# This compiles the 'litellm' executable specifically for this machine
RUN pip install 'litellm[proxy]'

COPY config.yaml /app/config.yaml

# 3. Run the executable directly
CMD ["litellm", "--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
