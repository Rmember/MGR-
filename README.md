MGR一键部署








1.1.3 重要参数的持久化
GTID相关参数
参数	comment
gtid_executed	执行过的所有GTID
gtid_purged	丢弃掉的GTID
gtid_mode	gtid模式
gtid_next	session级别的变量，下一个gtid
gtid_owned	正在运行的gtid
enforce_gtid_consistency	保证GTID安全的参数


while read读取文本内容

使用变量IFS作为分隔符读文件
说明：默认情况下IFS是空格，如果需要使用其它的需要重新赋值
