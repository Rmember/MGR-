MGR一键部署
MGR节点重新加入集群

1、查看最新的GTID
select TRANSACTIONS_COMMITTED_ALL_MEMBERS from performance_schema.replication_group_member_stats\G;\n
2、丢弃之前的GTID重新加入集群
SET @@GLOBAL.GTID_PURGED='be4533b6-b62e-462f-8a63-ef5db05cb60c:1-13'


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
