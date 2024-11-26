tofu init
./cleanup.sh
ansible-playbook -i inventory.ini configure_webserver.yml 
ansible-playbook -i inventory.ini configure_dbserver.yml 