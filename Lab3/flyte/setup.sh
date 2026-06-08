python3.11 -m venv flyte-env311
source flyte-env311/bin/activate
pip install --upgrade pip
pip install 'flyte[tui]'
flyte create config --local-persistence