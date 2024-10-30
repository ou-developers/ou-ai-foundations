#!/bin/bash

# Define a log file for capturing all output
LOGFILE=/var/log/cloud-init-output.log
exec > >(tee -a $LOGFILE) 2>&1

# Marker file to ensure the script only runs once
MARKER_FILE="/home/opc/.init_done"

# Check if the marker file exists
if [ -f "$MARKER_FILE" ]; then
  echo "Init script has already been run. Exiting."
  exit 0
fi

echo "===== Starting Cloud-Init Script ====="

# Enable ol8_addons and install necessary development tools
echo "Installing required packages..."
sudo dnf config-manager --set-enabled ol8_addons
sudo dnf install -y git libffi-devel bzip2-devel ncurses-devel readline-devel wget make gcc zlib-devel openssl-devel

# Install the latest SQLite from source
echo "Installing latest SQLite..."
cd /tmp
wget https://www.sqlite.org/2023/sqlite-autoconf-3430000.tar.gz
tar -xvzf sqlite-autoconf-3430000.tar.gz
cd sqlite-autoconf-3430000
./configure --prefix=/usr/local
make
sudo make install

# Verify the installation of SQLite
echo "SQLite version:"
/usr/local/bin/sqlite3 --version

# Ensure the correct version is in the path and globally
export PATH="/usr/local/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"
echo 'export PATH="/usr/local/bin:$PATH"' >> /home/opc/.bashrc
echo 'export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"' >> /home/opc/.bashrc

# Set environment variables to link the newly installed SQLite with Python build globally
echo 'export CFLAGS="-I/usr/local/include"' >> /home/opc/.bashrc
echo 'export LDFLAGS="-L/usr/local/lib"' >> /home/opc/.bashrc

# Source the updated ~/.bashrc to apply changes globally
source /home/opc/.bashrc

# Now switch to opc for user-specific tasks
sudo -u opc -i bash <<'EOF_OPC'

# Set environment variables
export HOME=/home/opc
export PYENV_ROOT="$HOME/.pyenv"
curl https://pyenv.run | bash

# Add pyenv initialization to ~/.bashrc for opc
cat << EOF >> $HOME/.bashrc
export PYENV_ROOT="\$HOME/.pyenv"
[[ -d "\$PYENV_ROOT/bin" ]] && export PATH="\$PYENV_ROOT/bin:\$PATH"
eval "\$(pyenv init --path)"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
EOF

# Ensure .bashrc is sourced on login
cat << EOF >> $HOME/.bash_profile
if [ -f ~/.bashrc ]; then
   source ~/.bashrc
fi
EOF

# Source the updated ~/.bashrc to apply pyenv changes
source $HOME/.bashrc

# Export PATH to ensure pyenv is correctly initialized
export PATH="$PYENV_ROOT/bin:$PATH"

# Install Python 3.11.9 using pyenv with the correct SQLite version linked
CFLAGS="-I/usr/local/include" LDFLAGS="-L/usr/local/lib" LD_LIBRARY_PATH="/usr/local/lib" pyenv install 3.11.9

# Rehash pyenv to update shims
pyenv rehash

# Set up vectors directory and Python 3.11.9 environment
mkdir -p $HOME/labs
cd $HOME/labs
pyenv local 3.11.9

# Rehash again to ensure shims are up to date
pyenv rehash

# Verify Python version in the labs directory
python --version

# Install required Python packages
pip install --no-cache-dir oci==2.129.1 scikit-learn==1.3.0 seaborn==0.13.2 pandas==2.2.2 numpy==1.26.4 ipywidgets==8.1.2

# Install JupyterLab
pip install --user jupyterlab

# Install OCI CLI
echo "Installing OCI CLI..."
curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh -o install.sh
chmod +x install.sh
./install.sh --accept-all-defaults

# Verify the installation
echo "Verifying OCI CLI installation..."
oci --version || { echo "OCI CLI installation failed."; exit 1; }

# Ensure all the binaries are added to PATH
echo 'export PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
source $HOME/.bashrc

# Copy files from the git repo labs folder to the labs directory in the instance
echo "Copying files from the 'labs' folder in the OU Git repository to the existing labs directory..."
REPO_URL="https://github.com/ou-developers/ou-ai-foundations.git"
FINAL_DIR="$HOME/labs"  # Existing directory on your instance

# Initialize a new git repository
git init

# Add the remote repository
git remote add origin $REPO_URL

# Enable sparse-checkout and specify the folder to download
git config core.sparseCheckout true
echo "labs/*" >> .git/info/sparse-checkout

# Pull only the specified folder into the existing directory
git pull origin main  # Replace 'main' with the correct branch name if necessary

# Move the contents of the 'labs' subfolder to the root of FINAL_DIR, if necessary
mv labs/* . 2>/dev/null || true  # Move files if 'labs' folder exists

# Remove any remaining empty 'labs' directory and .git folder
rm -rf .git labs

echo "Files successfully downloaded to $FINAL_DIR"

EOF_OPC

# Create the marker file to indicate the script has been run
touch "$MARKER_FILE"

echo "===== Cloud-Init Script Completed Successfully ====="
exit 0
