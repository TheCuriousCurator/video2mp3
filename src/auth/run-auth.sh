# source .env
# export $(cut -d= -f1 .env)
export $(< .env)
.venv/bin/python3 server.py