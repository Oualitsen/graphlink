package dev.graphlink.server.apq;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Enumeration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Component
public class GraphQlGetFilter extends OncePerRequestFilter {

    private static final String JSON = "application/json";

    private final ObjectMapper mapper = new ObjectMapper();

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !"GET".equals(request.getMethod()) || !"/graphql".equals(request.getRequestURI());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String query = request.getParameter("query");
        if (query != null && query.stripLeading().startsWith("mutation")) {
            response.sendError(HttpServletResponse.SC_METHOD_NOT_ALLOWED, "Mutations are not allowed over GET");
            return;
        }
        chain.doFilter(new PostRequest(request, toBody(request)), response);
    }

    private byte[] toBody(HttpServletRequest request) throws IOException {
        Map<String, Object> body = new LinkedHashMap<>();
        copy(request, "query", body, false);
        copy(request, "operationName", body, false);
        copy(request, "variables", body, true);
        copy(request, "extensions", body, true);
        return mapper.writeValueAsBytes(body);
    }

    private void copy(HttpServletRequest request, String name, Map<String, Object> body, boolean json)
            throws JsonProcessingException {
        String value = request.getParameter(name);
        if (value == null || value.isBlank()) return;
        body.put(name, json ? mapper.readValue(value, Map.class) : value);
    }

    private static final class PostRequest extends HttpServletRequestWrapper {

        private final byte[] body;

        PostRequest(HttpServletRequest request, byte[] body) {
            super(request);
            this.body = body;
        }

        @Override
        public String getMethod() {
            return "POST";
        }

        @Override
        public String getContentType() {
            return JSON;
        }

        @Override
        public String getHeader(String name) {
            return "Content-Type".equalsIgnoreCase(name) ? JSON : super.getHeader(name);
        }

        @Override
        public Enumeration<String> getHeaders(String name) {
            return "Content-Type".equalsIgnoreCase(name)
                    ? Collections.enumeration(List.of(JSON))
                    : super.getHeaders(name);
        }

        @Override
        public Enumeration<String> getHeaderNames() {
            List<String> names = Collections.list(super.getHeaderNames());
            if (names.stream().noneMatch("Content-Type"::equalsIgnoreCase)) names.add("Content-Type");
            return Collections.enumeration(names);
        }

        @Override
        public int getContentLength() {
            return body.length;
        }

        @Override
        public long getContentLengthLong() {
            return body.length;
        }

        @Override
        public ServletInputStream getInputStream() {
            ByteArrayInputStream stream = new ByteArrayInputStream(body);
            return new ServletInputStream() {
                @Override
                public int read() {
                    return stream.read();
                }

                @Override
                public boolean isFinished() {
                    return stream.available() == 0;
                }

                @Override
                public boolean isReady() {
                    return true;
                }

                @Override
                public void setReadListener(ReadListener listener) {
                }
            };
        }

        @Override
        public BufferedReader getReader() {
            return new BufferedReader(new InputStreamReader(getInputStream(), StandardCharsets.UTF_8));
        }
    }
}
