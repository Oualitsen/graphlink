package com.graphlink;

import com.graphlink.generated.client.DefaultGraphLinkClientAdapter;
import com.graphlink.generated.client.DefaultGraphLinkWebSocketAdapter;
import com.graphlink.generated.client.GraphLinkClient;
import com.graphlink.generated.client.JacksonGraphLinkJsonCodec;
import com.graphlink.generated.types.Person;
import okhttp3.OkHttpClient;

import java.util.List;

public class Main {



    public static void main(String[] args) throws Exception {
        final String url = "http://localhost:8080/graphql";
        final String wsurl = "ws://localhost:8080/graphql";
        final var httpClient = new OkHttpClient();
        final GraphLinkClient client = new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(url, null, httpClient),
                new JacksonGraphLinkJsonCodec(),
                new JacksonGraphLinkJsonCodec(),
                new DefaultGraphLinkWebSocketAdapter(wsurl, null, httpClient)

        );

        List<Person> persons = client.queries.persons().getPersons();

        persons.forEach(p -> {
            System.out.println("p = " + p.name() + ", " + p.age());
        });

        client.subscriptions.personAdded((data) -> {
            System.out.println("########## data = " + data.getPersonAdded().name());
        });
        client.subscriptions.personAdded((data) -> {
            System.out.println("@@@@@@@@@@ data2 = " + data.getPersonAdded().name());
        });

        Thread.sleep(20000);
    }
}
