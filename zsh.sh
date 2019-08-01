sudo apt install git-core zsh
curl -OL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh
chmod +x ./install.sh
./install.sh
rm ./install.sh
sudo chsh -s $(which zsh)
cd ~/.oh-my-zsh/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions
compaudit | xargs chmod g-w,o-w ~/.oh-my-zsh/plugins
echo "Update zsh plugins to include zsh-syntax-highlighting, zsh-autosuggestions"
nano ~/.zshrc

