tofu init
./cleanup.sh
ansible-playbook -i inventory.ini installation/configure_webserver.yml 
ansible-playbook -i inventory.ini installation/configure_dbserver.yml 