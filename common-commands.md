  GNU nano 7.2                                                                             readme.md                                                                                       
# To modify llama server config
sudo nano /etc/llama-server.conf

# After making changes to the llama server config
sudo systemctl daemon-reload
sudo systemctl restart llama-server

# To show llama server logs
sudo journalctl -u llama-server -f