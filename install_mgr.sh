#!/bin/bash

#########################################
#
# Install MqSQL Group Replication
#
# $1 - install media file: e.g. mysql-5.7.20-linux-glibc2.12-x86_64.tar.gz
# $2 - base directory for mysql: /usr/local/mysql
# $3 - port of mysql: 3306
# $4 - inner port of group replication: 33061
# $5 - 配置文件绝对路径: /appdata/mgrprofile/my.cnf
# $6 - data directory for mysql: /appdata/mgrdata
# $7 - 数据库管理员用户root用户密码: Passw0rd!
# $8 - 数据库探测用户haproxy密码: Passw0rd!
# $9 - 数据库探测读端口: 6447
# $10 - 数据库探测写端口: 6446
# $11 - 数据库实例服务名: mysqld
# $12+ - server ip list
#
#########################################

function checkretcode(){
	retcode=$?
	if [[ ! ${retcode} = 0 ]]; then
		echo error! retcode is ${retcode}
		exit
	fi
}

if [ $# -lt 11 ]; then
	echo Error: number of parameter illegal
	echo Usage: $0 mysql_install_media mysql_install_base client_port mgr_port profile_file_path data_dir root_pwd haproxy_pwd read_check_port write_check_port service_name server_ip...
	exit
fi

mysql_install_media=$1
mysql_install_base=$2
client_port=$3
mgr_port=$4
profile_file_path=$5
data_dir=$6
root_pwd=${7}
haproxy_pwd=${8}
read_check_port=${9}
write_check_port=${10}
service_name=${11}

# shift for server ip list
for x in {1..11}
do
	shift;
done

# 计算配置文件的目录
profile_dir=`dirname ${profile_file_path}`

echo ============================================================
echo ========== install media for MySQL: $mysql_install_media
echo ========== base directory for MySQL: $mysql_install_base
echo ========== port for MySQL client: $client_port
echo ========== port for MySQL Group Replication: $mgr_port
echo ========== profile full path for MySQL: $profile_file_path
echo ========== data directory for MySQL: $data_dir
echo ========== db password for user root: ${root_pwd}
echo ========== db password for user haproxy: ${haproxy_pwd}
echo ========== check port for mgr read: ${read_check_port}
echo ========== check port for mgr write: ${write_check_port}
echo ========== service_name: ${service_name}
echo ========== server ip list: $*

echo ============================================================
echo 
sleep 1
read -p "Please confirm the information above(Y/N):" yn
if [[ ! ${yn} = 'Y' ]] && [[ ! ${yn} = 'y' ]]; then
	echo
	echo exit...
	echo
	exit
fi

# 跳转到本地目录
DIR="$( cd "$( dirname "$0" )" && pwd )"
cd ${DIR}

# check file exist
echo $mysql_install_media
if [ ! -f $mysql_install_media ];then
	echo ERROR: File $mysql_install_media not exist
	exit;
fi

file_name=${mysql_install_media##*/}

if [[ ! $file_name =~ .+\.tar\.gz$ ]]; then
	echo ERROR: mysql_install_media only support tar.gz
	exit;
fi

if [ $# -gt 9 ]; then
	echo ERROR: server list count can not exceed 9
	exit;
fi

yum -y install openssh-clients
yum -y install coreutils

echo
echo ========== echo ========== server list: $*
echo ============================================================
echo
echo ========== check hostname for each other: $*
	./hostname_check.sh $*
	checkretcode
echo ========== check hostname for each other done!
echo 
echo ========== config hosts for each other: $*
	./hosts.sh $*
echo ========== config hosts for each other done!

# remote tmp dir for place
tmp_dir=/tmp/mysql-install/mgr-$RANDOM

server_id=0

yum -y install uuid
uuid=`uuid`

# set MGR variables
group_replication_group_seeds=
group_replication_ip_whitelist=

for i in $*
do
	if [ ! $group_replication_group_seeds ]; then
		group_replication_group_seeds=$i:$mgr_port
	else
		group_replication_group_seeds=$group_replication_group_seeds,$i:$mgr_port
	fi
	if [ ! $group_replication_ip_whitelist ]; then
		group_replication_ip_whitelist=$i
	else
		group_replication_ip_whitelist=$group_replication_ip_whitelist,$i
	fi
done

for i in $*
do

	echo

	# 检测客户端是7还是6版本
	echo ========== [$i] check os version
	
	command="if [ -f /bin/systemctl ]; then echo 7; else echo 6; fi"
	os_version=`ssh root@$i $command`

	echo ========== [$i] check os version $os_version done!
	
	echo
	
	echo ========== [$i] check client port for bind
	command="lsof -i:$client_port"
	ans=`ssh root@$i $command`
	if [ $ans ]; then
		echo ========== [$i] client port: $client_port already in use
		echo ========== [$i] install failure
		exit
	else
		echo ========== [$i] client port: $client_port not in use
	fi
	echo ========== [$i] check client port for bind done!
	
	echo

	echo ========== [$i] check read port for bind
	command="lsof -i:${read_check_port}"
	ans=`ssh root@$i $command`
	if [ $ans ]; then
		echo ========== [$i] read port: ${read_check_port} already in use
		echo ========== [$i] install failure
		exit
	else
		echo ========== [$i] read port: ${read_check_port} not in use
	fi
	echo ========== [$i] check read port for bind done!
	
	echo

	echo ========== [$i] check write port for bind
	command="lsof -i:${write_check_port}"
	ans=`ssh root@$i $command`
	if [ $ans ]; then
		echo ========== [$i] write port: ${write_check_port} already in use
		echo ========== [$i] install failure
		exit
	else
		echo ========== [$i] write port: ${write_check_port} not in use
	fi
	echo ========== [$i] check write port for bind done!
	
	echo
	
	echo ========== [$i] check profile_file
		command="if [ -f $profile_file_path ]; then echo 1; else echo 0; fi"
		ans=`ssh root@$i $command`
		echo ans is $ans
		if [ $ans -eq 1 ]; then
			echo ========== [$i] profile_file: $profile_file_path exist! please check first
			echo ========== [$i] install failure
			exit
		fi
	echo ========== [$i] check profile_file done!
	
	echo
	
		echo ========== [$i] check data_dir
		command="if [ -d $data_dir ]; then echo 1; else echo 0; fi"
		ans=`ssh root@$i $command`
		if [ $ans -eq 1 ]; then
			echo ========== [$i] data_dir: $data_dir exist! please check first
			echo ========== [$i] install failure
			exit
		fi
	echo ========== [$i] check data_dir done!

	echo
	
		echo ========== [$i] check service name
		if [[ ${os_version} = 7 ]]; then
            command="systemctl status $service_name"
		else
			command="service $service_name status"
		fi
		ans=`ssh root@$i $command`
		ans=$?

		if [ $ans -eq 0 ]; then
			echo ========== [$i] service name: $service_name exist! please check first
			echo ========== [$i] install failure
			exit
		fi

	echo ========== [$i] check service name done!
	
	echo ========== [$i] create tmp_dir

		echo ========== [$i] tmp_dir: $tmp_dir
		ssh root@$i "mkdir -p $tmp_dir"
		checkretcode

	echo ========== [$i] create tmp_dir done!

	echo
	
	echo ========== [$i] install yum required

		scp yum.sh root@$i:$tmp_dir
		checkretcode
		ssh root@$i "cd $tmp_dir; chmod +x yum.sh; ./yum.sh"
		checkretcode
		scp -r ./send root@$i:${tmp_dir}
		checkretcode
		
	echo ========== [$i] install yum required done!

	echo
	
	echo ========== [$i] install xtrabackup required
		ssh root@$i "sh ${tmp_dir}/send/xtrabackupinstall.sh"
		checkretcode
	echo ========== [$i] install xtrabackup required done!

	echo

	echo ========== [$i] install mysql requirements files

		scp mysql_requirements.sh root@$i:$tmp_dir
		checkretcode
		ssh root@$i "cd $tmp_dir; chmod +x mysql_requirements.sh; ./mysql_requirements.sh"
		checkretcode

	echo ========== [$i] install mysql requirements files done!

	echo

	echo ========== [$i] create mysql user "&" group

		scp user.sh root@$i:$tmp_dir
		checkretcode
		ssh root@$i "cd $tmp_dir; chmod +x user.sh; ./user.sh"
		checkretcode
		
	echo ========== [$i] create mysql user "&" group done!

	echo

	echo ========== [$i] copy mysql

	file_dir=${file_name%.*.*}
	
	# check file exists
	command="if [ -f ${mysql_install_base}/bin/mysqld ]; then echo 1; else echo 0; fi"
	ans=`ssh root@$i $command`
	
	# 服务端文件存在
	if [[ $ans -eq 1 ]]; then
	
		echo ========== [$i] MySQL Executable File exist, checking...
		
		# 计算服务端MD5值
		command="md5sum $mysql_install_base/bin/mysqld | awk '{print \$1}'"
		md5remote=`ssh root@$i $command`
		echo md5sum for remote mysqld is ${md5remote}
		
		# 计算本地MD5值
		if [[ ! -f ${file_dir}/bin/mysqld ]]; then
			tar xf $mysql_install_media
			checkretcode
		fi
		
		md5local=`md5sum ${file_dir}/bin/mysqld | awk '{print $1}'`
		echo md5sum for local mysqld is ${md5local}
		
		if [[ ${md5remote} = ${md5local} ]]; then
			ans=0
		else
			ans=1
		fi
			
		echo compare_ans is ${ans}
		
		if [[ $ans -eq 0 ]]; then
			echo ========== [$i] install mysqld file equal with exist file: $mysql_install_base/bin/mysqld
			echo ========== [$i] using current MySQL Executable File:  $mysql_install_base
		else
			echo ========== [$i] install mysqld file $tmp_dir/${file_dir}/bin/mysqld not equal with exist file: $mysql_install_base/bin/mysqld
			echo ========== [$i] install failure!;
			exit
		fi
			
	else
	
		echo transfer $mysql_install_media
		scp $mysql_install_media root@$i:$tmp_dir
		checkretcode
		
		# 上级菜单
		mysql_install_base_parent=`dirname $mysql_install_base`
		
		echo extract $mysql_install_media
		ssh root@$i "cd $tmp_dir; tar xf $file_name -C ${mysql_install_base_parent}"
		checkretcode
		
		command="mv ${mysql_install_base_parent}/${file_dir} $mysql_install_base"
		ssh root@$i $command
		checkretcode
		
	fi
		


	echo ========== [$i] copy mysql done!

	echo

	echo ========== [$i] install mysql

		server_id=$((server_id+1))
		weight=$((10-server_id))
		curr_ip=$i

		cat my.cnf.template | sed "s/{{client_port}}/$client_port/g" \
							| sed "s/{{mgr_port}}/$mgr_port/g" \
							| sed "s/{{uuid}}/$uuid/g" \
							| sed "s/{{server_id}}/$server_id/g" \
							| sed "s/{{weight}}/$weight/g" \
							| sed "s/{{curr_ip}}/$curr_ip/g" \
							| sed "s/{{group_replication_group_seeds}}/$group_replication_group_seeds/g" \
							| sed "s/{{group_replication_ip_whitelist}}/$group_replication_ip_whitelist/g" \
							| sed "s:{{mysql_install_base}}:$mysql_install_base:g" \
							| sed "s:{{data_dir}}:$data_dir:g" \
		> my.cnf
		checkretcode
		
		# get socket file
		socket_file=`grep socket my.cnf | grep -P '=\s.*' -o | sed 's/=//g' | sed 's/\s//g'`
		echo socket_file=${socket_file}
		
		if [[ ! ${socket_file} ]]; then
			echo ERROR: socket_file is empty
			exit
		fi

		# get pid file
		pid_file=`grep pid my.cnf | grep -P '=\s.*' -o | sed 's/=//g' | sed 's/\s//g'`
		echo pid_file=${pid_file}
		
		if [[ ! ${pid_file} ]]; then
			echo ERROR: pid_file is empty
			exit
		fi
		
		ssh root@$i "mkdir -p $profile_dir"
		checkretcode
		echo transfer my.cnf to remote
		scp my.cnf root@$i:$profile_file_path
		checkretcode
		ssh root@$i "chown mysql:mysql $profile_file_path"
		checkretcode
		echo ========== [$i] MqSQL profile $profile_file_path created

		# remove tmp file
		rm ./my.cnf

		# 初始化数据库
		command="$mysql_install_base/bin/mysqld --no-defaults --user=mysql --basedir=$mysql_install_base --datadir=$data_dir --initialize-insecure"
		echo ========== [$i] exec command: $command
		ssh root@$i $command
		checkretcode
		echo ========== [$i] database created

		# 对于RHEL7系列，配置systemd服务 开始
		if [[ ${os_version} = 7 ]]; then
			cat mysqld.service.template | sed "s:{{PID_FILE}}:$pid_file:g" \
							| sed "s:{{MYSQL_HOME}}:$mysql_install_base:g" \
							| sed "s:{{CONFIG_FILE}}:$profile_file_path:g" \
			> mysqld.service
			checkretcode
			
			scp mysqld.service root@$i:/usr/lib/systemd/system/${service_name}.service
			checkretcode
			
			ssh root@$i "systemctl enable ${service_name}"
			checkretcode
			
			ssh root@$i "systemctl start ${service_name}"
			checkretcode
			
		else
			# 对于RHEL6系列，配置service服务
			
			cat mysqld.service.rhel6.template \
							| sed "s:{{MYSQL_HOME}}:$mysql_install_base:g" \
							| sed "s:{{CONFIG_FILE}}:$profile_file_path:g" \
			> mysqld.service.rhel6
			checkretcode
			
			scp mysqld.service.rhel6 root@$i:/etc/rc.d/init.d/${service_name}
			checkretcode
			
			ssh root@$i "chmod +x /etc/rc.d/init.d/${service_name}"
			checkretcode
			
			ssh root@$i "service ${service_name} start"
			checkretcode
			
			ssh root@$i "chkconfig ${service_name} on"
			checkretcode

		fi
		
		
		# 配置systemd服务 结束
		
		
		# 等待执行启动
		ok=0
		command="nc -z 127.0.0.1 ${client_port} &"

		# 循环验证端口已开启
		for t in {1..30}
		do
			
			sleep 2
			
			ssh root@$i ${command}
			# 校验返回码
			RET_CODE=$?
			if [[ $RET_CODE = 0 ]]; then
				echo ========== [$i] mysql start success
				ok=1
				break
			else
				echo waiting...
			fi
		done

		if [[ ${ok} = 0 ]]; then
			echo ========== [$i] start database error! RET_CODE=$RET_CODE
			echo
			echo ========== [$i] START DATABASE INSTANCE ERROR! ==========
			exit
		fi

		sleep 3
		
		# 生成创建用户的sql文件
		cat db_user.sql.template | sed "s:{{root_pwd}}:$root_pwd:g" > db_user.sql
		checkretcode
		
		# 传递到服务器执行
		echo ========== [$i] create database user "&" privileges
		scp db_user.sql root@$i:$tmp_dir
		checkretcode
		command="$mysql_install_base/bin/mysql -S${socket_file} < $tmp_dir/db_user.sql"
		echo ========== [$i] exec command: $command
		ssh root@$i $command
		checkretcode
		echo ========== [$i] create database user "&" privileges done!

		echo
		
		if [ ! $master_node ]; then
			echo ========== [$i] is master
			scp start_mgr_master.sql root@$i:$tmp_dir/start_mgr.sql
			checkretcode
			master_node=$i
		else
			echo ========== [$i] is slave
			scp start_mgr_slave.sql root@$i:$tmp_dir/start_mgr.sql
			checkretcode
		fi

		echo
		
		echo ========== [$i] start mgr
		command="$mysql_install_base/bin/mysql -uroot -h127.0.0.1 -P${client_port} -p${root_pwd} < $tmp_dir/start_mgr.sql"
		echo ========== [$i] exec command: $command
		ssh root@$i $command
		checkretcode
		echo ========== [$i] start mgr done!
		
		echo
		
		echo ========== [$i] mgr check service 
		
		scp ./install-mgr-check-local.sh root@$i:$tmp_dir
		checkretcode
		ssh root@$i "cd $tmp_dir; chmod +x install-mgr-check-local.sh;"
		checkretcode
		
		command="cd $tmp_dir; ./install-mgr-check-local.sh ${client_port} ${mysql_install_base} ${root_pwd} haproxy ${haproxy_pwd} ${read_check_port} ${write_check_port}"
		ssh root@$i $command
		checkretcode
		echo ========== [$i] mgr check service done!
		echo
		
		echo ========== [$i] list mgr node
		scp list_mgr.sql root@$i:$tmp_dir/list_mgr.sql
		checkretcode
		command="$mysql_install_base/bin/mysql -uroot -h127.0.0.1 -P${client_port} -p${root_pwd} < $tmp_dir/list_mgr.sql"
		echo ========== [$i] exec command: $command
		ssh root@$i $command
		checkretcode
		echo ========== [$i] list mgr node done!
		
		echo
		
	echo ========== [$i] install mysql done!

done

echo
echo ============================================================
echo ==========  Congratulations! MGR INSTALL SUCCESS! ==========
echo ==========  Install MqSQL Group Replication Done! ==========
echo ============================================================
echo

