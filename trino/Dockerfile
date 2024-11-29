FROM trinodb/trino:466

RUN rm /usr/lib/trino/plugin/apache-ranger/org.apache.ranger_ranger-plugins-common-2.5.0.jar 
RUN rm /usr/lib/trino/plugin/apache-ranger/org.apache.ranger_ranger-plugins-audit-2.5.0.jar

COPY ./dist/*.jar /usr/lib/trino/plugin/apache-ranger/

# https://repo1.maven.org/maven2/org/opensearch/client/opensearch-rest-client/2.15.0/opensearch-rest-client-2.15.0.jar
# https://repo1.maven.org/maven2/org/opensearch/client/opensearch-java/2.15.0/opensearch-java-2.15.0.jar
# wget https://repo1.maven.org/maven2/org/codehaus/jackson/jackson-jaxrs/1.9.13/jackson-jaxrs-1.9.13.jar
# wget https://repo1.maven.org/maven2/org/codehaus/jackson/jackson-core-asl/1.9.13/jackson-core-asl-1.9.13.jar
# wget https://repo1.maven.org/maven2/jakarta/json/jakarta.json-api/2.1.3/jakarta.json-api-2.1.3.jar
# wget https://repo1.maven.org/maven2/org/codehaus/jackson/jackson-mapper-asl/1.9.13/jackson-mapper-asl-1.9.13.jar
# https://repo1.maven.org/maven2/org/codehaus/jackson/jackson-mapper-asl/1.9.13/jackson-mapper-asl-1.9.13.jar
# https://repo1.maven.org/maven2/org/codehaus/jackson/jackson-xc/1.9.13/jackson-xc-1.9.13.jar
# https://repo1.maven.org/maven2/org/openjdk/nashorn/nashorn-core/15.4/nashorn-core-15.4.jar
# https://repo1.maven.org/maven2/org/eclipse/parsson/parsson/1.1.6/parsson-1.1.6.jar