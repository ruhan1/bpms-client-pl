# bpms-client-pl
Perl client to create bpms 6.x process instance and perform tasks via rest api. It support BASIC HTTP authentication and Kerberos (kinit) authentication. 

##1. Prerequisite

$ cpan

cpan> install LWP::Authen::Negotiate XML::Simple Switch Config::Simple

##2. Config (first time)

./maitai.pl conf homeUrl=http://localhost:8080

##3. System variable (optional)

$ export BPMS_HOME=http://localhost:8080 (if not set homeUrl)

$ export DEBUG=1 (to open debug)

##4. User Kerberos authentication (Optional)

$ kinit

##5. Examples

./maitai.pl deployment

./maitai.pl deployment processes -deploymentId com.myorganization.myprojects:test:1.9

./maitai.pl process start -deploymentId com.myorganization.myprojects:test:1.9 -processDefId test.testusertask -d taskOwner=ruhan -d description="a test"

./maitai.pl task query -D potentialOwner=ruhan

./maitai.pl task start -taskId 5

./maitai.pl task complete -taskId 5 -d approval_=false
