package com.sec4us.lab.sonarhelper;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sec4us.lab.sonarhelper.config.SonarConfig;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;

public class SonarHelper {

    private static final int PAGE_SIZE = 500;

    public static void main(String[] args) throws Exception {
        String baseUrl = stripTrailingSlash(SonarConfig.SONAR_URL);
        String basicAuth = "Basic " + Base64.getEncoder().encodeToString(
                (SonarConfig.SONAR_ADMIN_USER + ":" + SonarConfig.SONAR_ADMIN_PASSWORD)
                        .getBytes(StandardCharsets.UTF_8));

        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
        ObjectMapper mapper = new ObjectMapper();

        System.out.printf("Connecting to SonarQube at %s as %s%n",
                baseUrl, SonarConfig.SONAR_ADMIN_USER);

        int page = 1;
        int total = -1;
        int printed = 0;

        while (true) {
            URI uri = URI.create(String.format(
                    "%s/api/projects/search?ps=%d&p=%d", baseUrl, PAGE_SIZE, page));

            HttpRequest req = HttpRequest.newBuilder(uri)
                    .header("Authorization", basicAuth)
                    .header("Accept", "application/json")
                    .timeout(Duration.ofSeconds(30))
                    .GET()
                    .build();

            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() / 100 != 2) {
                System.err.printf("SonarQube returned HTTP %d: %s%n",
                        resp.statusCode(), resp.body());
                System.exit(1);
            }

            JsonNode root = mapper.readTree(resp.body());
            JsonNode components = root.path("components");

            if (total < 0) {
                total = root.path("paging").path("total").asInt(0);
                System.out.printf("Found %d project(s).%n", total);
                System.out.println("----------------------------------------");
                System.out.printf("%-40s %-30s %s%n", "KEY", "NAME", "VISIBILITY");
                System.out.println("----------------------------------------");
            }

            if (!components.isArray() || components.size() == 0) {
                break;
            }

            for (JsonNode c : components) {
                System.out.printf("%-40s %-30s %s%n",
                        c.path("key").asText(""),
                        c.path("name").asText(""),
                        c.path("visibility").asText(""));
                printed++;
            }

            if (printed >= total) {
                break;
            }
            page++;
        }

        System.out.println("----------------------------------------");
        System.out.printf("Done. Listed %d project(s).%n", printed);
    }

    private static String stripTrailingSlash(String url) {
        return url.endsWith("/") ? url.substring(0, url.length() - 1) : url;
    }
}
