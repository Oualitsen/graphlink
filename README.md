# Retrofit GraphQL for Dart
​
**retrofit_graphql** or `Retrofit GraphQL` for Dart is a powerful code generation tool that simplifies working with GraphQL in `Dart` and `Flutter` projects.
Unlike other tools, `Retrofit GraphQL` generates code that is `null-safe`
 This tool automates the generation of Dart classes for types, enums, inputs. Additionally, it creates a GraphQL client for streamlined query, mutation and subscription execution. The code generator can also be configured to generate fragments that simplify attribute access.
​
## Table of Contents
​
1. [Installation](#installation)
2. [Code Generation](#code-generation)
3. [GraphQL Client](#graphql-client)
4. [Generate Code with Build Runner](#generate-code-with-build-runner)
5. [License](#license)
​
## Installation
​
To add **Retrofit GraphQL for Dart** to your project, follow these steps:
​
- Using Dart's `pub` package manager:
​
  ```bash
        pub add --dev retrofit_graphql
  ```
​
- If you are working with Flutter:
​
  ```bash
        flutter pub add --dev retrofit_graphql
  ```

- You will also need to add `json_serializable` to your dependecies for `JSON` serialization/deserialization
​
## Getting Started
​
To begin using Retrofit GraphQL in your project, make sure to follow these initial steps:
​
1. **GraphQL Schema**:
​
   - Ensure you have a well-defined GraphQL schema that outlines your data structures and operations.
   you usually get it from your backend server.
​
2. **Configuration**:
​
   - Configure the Retrofit GraphQL library by specifying the path to your GraphQL schema and any custom type mappings in the `build.yaml` file.
   Here is an example of `build.yaml`
   
```
targets:
  $default:
    builders:
      retrofit_graphql|aggregatingBuilder:
        enabled: true
        generate_for:
          include:
            - lib/**/*.graphql
        options:
        # following are going to be mappings between scalars and dart types
          Long: int
          ID: String
          generateAllFieldsFragments: true
          nullableFieldsRequired: false
          # needs "generateAllFieldsFragments" = true
          # This feature allows to generate all queries without having to declare them.
          # You can still declare custom queries even if this is enabled
          autoGenerateQueries: true
          autoGenerateQueriesDefaultAlias: "data"
```
​
3. **Generate Dart Code**:
​
   - Use Retrofit GraphQL to automatically generate necessary Dart classes based on your schema, queries, mutations, and subscriptions.
​
4. **GraphQL Client**:
   - The tool automatically creates a GraphQL client to handle mutations, queries and subscriptions efficiently.
​
## Code Generation
​
The code generation process involves:
​
1. **Schema Parsing**:
​
   - The tool parses your GraphQL schema, queries, and mutations to generate Dart classes.
​
2. **Type Classes**:
​
   - Generates classes for representing data structures defined in your schema.
​
3. **Enums**:
​
   - Creates enums for enumerated types in your schema.
​
4. **Input Classes**:
​
   - Generates input classes for GraphQL input types, simplifying data interaction.
​
5. **JSON Serialization/Deserialization**:
​   - Retrofit GraphQL does not generate code that serialize/deserialize from/to JSON, you need to use `json_serializable` in your dependecies 
   - Includes a `JsonSerializableGenerator` to handle JSON serialization and deserialization.
​
6. **Custom Type Names**:
​
   - The tool recognizes the `@gqTypeName(name:"YourCustomName")` directive in your GraphQL schema, allowing you to specify custom names for response types. This feature enables you to control the naming of generated Dart classes for specific response types.
​
7. **Generate All Fields Fragments**:
​
   - By enabling the `generateAllFieldsFragments` option in your build configuration, you can automatically generate fragments for all types. These fragments simplify the retrieval of all attributes for a specific class, allowing you to access them like this: `{... _all_fields_YourClassName}` or just `{... _all_fields}`. This feature enhances the ease of working with the generated Dart classes.
​
## GraphQL Client

​
1. **Initialize the Client**:
​
To initialize the GraphQL client, you can use the following code. This configuration sets up the client with WebSocket and HTTP adapters:
​
```dart
    const wsUrl = "ws://localhost:8080/graphql";
    const url = "http://localhost:8080/graphql";
​
    // Create a WebSocket channel adapter for subscriptions.
    var wsAdapter = WebSocketChannelAdapter(wsUrl); // this is optional
​
    // Define an HTTP request function for queries and mutations.
    var httpFn = (payload) => http
        .post(Uri.parse(url),
            body: payload, headers: {"Content-Type": "application/json"})
        .asStream()
        .map((response) => response.body)
        .first;
​
    // Create a GQClient with the HTTP and WebSocket adapters.
    var client = GQClient(httpFn, wsAdapter);
```
​
2. **Execute GraphQL Operations**:
​
You can use the GraphQL client to send queries, mutations, and subscriptions. The following code example demonstrates how to retrieve data with a query:
​
```dart
     // Send a query to the server and receive the response as a Future.
    var response = await client.queries.getUserById(id: "test");
   
     // handle the value found in response.getUserById
     // if the request fails, an exeption will be throuwn
     
```
​
The client.queries.getUser method sends a GraphQL query to the server, and the response is processed in the stream. You can adapt this example to perform mutations and subscriptions as needed.
​
3. **Working with Data Payloads**:
​
   The client seamlessly handles data payloads using the provided adapter for JSON data transmission. It Generates `inputs` as `classes` using the same name with named parameters. 

​
4. **Error Handling**:

​
   The generated client includes error handling mechanisms for GraphQL errors and exceptions.
​
## Generate Code with Build Runner:
​
After setting up Retrofit GraphQL in your project, you need to generate code using the `build_runner` tool. To do this, execute the following command in your project's root directory:
​
```bash
    flutter pub run build_runner watch -d
```
​
This command triggers the code generation process, which creates a "generated" folder containing the following generated Dart code:
​
- client.gq.dart: This folder contains generated code for all your queries, mutations, and subscriptions.
- types.gq.dart: Contains code for all generated type classes.
- input.gq.dart: Includes code for generated input classes.
- enums.gq.dart: Contains code for generated enum classes.
​
Make sure to include these generated files in your project as they are essential for working with Retrofit GraphQL. These files will be automatically updated as you modify your GraphQL schema and queries.
​
## License
​
Retrofit GraphQL is open-source software released under the MIT License. Review the [LICENSE](LICENSE) file for detailed licensing terms.
​
For project updates, additional information, reporting issues, or making suggestions, please visit our [GitHub repository](https://github.dev/Oualitsen/Retrofi-Graphql-For-Dart).
​
Thank you for choosing Retrofit GraphQL for Dart to streamline your GraphQL development and data handling.