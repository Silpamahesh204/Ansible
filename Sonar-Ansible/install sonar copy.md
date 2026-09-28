Install Sonar - transcription from CameraRecording-421FDD8B-1DD2-4CF2-9778-BBF6510E6CDB.mp4

Download and extract
--------------------
From: https://binaries.sonarsource.com/?prefix=Distribution/sonarqube/

The note shows a curl command downloading an Enterprise ZIP from an internal
Artifactory URL to sonarqube-10.1.0.73491.zip. The embedded user/credential
and internal download URL are omitted here.

[sonar@t0016vmsq01r01d ~]$ cd /opt/apps
[sonar@t0016vmsq01r01d ~]$ unzip sonarqube-10.1.0.73491.zip
Archive: sonarqube-10.1.0.73491.zip
[The archive expands a sonarqube-10.1.0.73491 directory and its files.]
[sonar@t0016vmsq01r01d apps]$ ll
[The sonarqube-10.1.0.73491 directory is owned by sonar:sonar.]
[sonar@t0016vmsq01r01d sonar]$ vi sonarqube-10.1.0.73491/conf/sonar.properties

Update sonar.properties
-----------------------
Update the sonar.properties file at the location below:
[sonar@t0016vmsq01r01d conf]$ pwd
/opt/apps/sonarqube-10.1.0.73491/conf
[sonar@t0016vmsq01r01d conf]$ ll
[sonar.properties is owned by sonar:sonar.]

# The schema must be created first.
sonar.jdbc.username=sonar
sonar.jdbc.password=[redacted]

# PostgreSQL 11 or greater
# By default the schema named "public" is used. It can be overridden with
# the parameter "currentSchema".
#sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube?currentSchema=my_schema
sonar.jdbc.url=jdbc:postgresql://t0016-psqlsq01r01-d.postgres.database.azure.com:5432/sonar?currentSchema=sonar

# Defaults are respectively <installation home>/data and <installation home>/temp.
sonar.path.data=/var/sonar/data
sonar.path.temp=/var/sonar/temp

Start and inspect SonarQube
---------------------------
cd sonarqube-10.1.0.73491/bin/linux-x86-64/
./sonar.sh start

Validate all logs at the location below and check for errors or warnings:
[sonar@t0016vmsq01r01d logs]$ pwd
/opt/apps/sonarqube-10.1.0.73491/logs

Visible files include ce.log, es.log, nohup.log, README.txt, sonar.log, and web.log.

Once Sonar starts, a process ID file should appear:
[sonar@t0016vmsq01r01d linux-x86-64]$ ls -lart
sonar.sh
SonarQube.pid

Check status and health
-----------------------
curl -u [username]:[password] --request GET http://localhost:9000/api/system/health
{"health":"GREEN","causes":[]}

curl -u [username]:[password] --request GET http://localhost:9000/api/system/info

Key values visible in the response:
- Health: GREEN
- Version: 10.1.0.73491
- Edition: Enterprise
- Home Dir: /opt/apps/sonarqube-10.1.0.73491
- Data Dir: /var/sonar/data
- Temp Dir: /var/sonar/temp
- Processors: 8
- Database: PostgreSQL 16.3, user sonar
- JDBC driver version: 42.6.0
- Java: OpenJDK 17.0.12, Red Hat
- Search state: GREEN
- Database password field in the JSON is masked.

The full /api/system/info output also lists bundled analyzers, JVM and
compute-engine metrics, search indexes, and SonarQube settings. It is a long
single-line JSON response, repeated over several screens in the recording.

The next visible curl request queries localhost:9000/api/projects/search.
Its JSON response has paging data (page 1, page size 100, total 171) and a
large components array with project keys, names, visibility, analysis dates,
and revisions. The video scrolls through part of this response. Individual
project records are omitted because the recording is blurry and they are
not installation commands.

Transcription notes
-------------------
This is a moving recording of a OneNote page. Some shell prompts and archive
output are slightly blurred. The ZIP extraction output appears to mention
/opt/sonar in places, while the later working directory and system info show
/opt/apps; verify the actual deployment path before using the commands.
Credentials in the recorded curl commands and properties are redacted.
