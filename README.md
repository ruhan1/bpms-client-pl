# bpms-client-pl
Perl client to create bpms 6.x process instance and perform tasks via rest api. It support BASIC HTTP authentication and Kerberos (kinit) authentication. 

##1. Prerequisite

cpan> install LWP::Authen::Negotiate XML::Parser XML::Simple Switch

If install XML::Simple fails, try yum install expat-devel

##2. System variables

$ export BPMS_HOME=http://localhost:8080 (default is https://maitai-bpms-01.app.test.eng.nay.redhat.com)

$ export DEBUG=1 (if you need debug)

##3. User Kerberos authentication (Optional)

$ kinit

##4. Examples

./maitai.pl deployment

./maitai.pl process start -deploymentId com.myorganization.myprojects:test:1.9 -processDefId test.testusertask -d taskOwner=ruhan -d description="a test"

./maitai.pl task query -D potentialOwner=ruhan

./maitai.pl task start -taskId 5

./maitai.pl task complete -taskId 5 -d approval_=false
