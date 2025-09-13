# PhotonAPI

PhotonAPI is a lightweight, high performance, type-safe web API framework for Free Pascal. It is designed to provide a clean way to register routes, enforce parameter types, and return structured JSON responses.  

PhotonAPI also includes built-in [OpenAPI](https://swagger.io/specification/) specification generation and a [Swagger UI](https://swagger.io/) interface for interactive documentation.

## Features
PhotonAPI is designed for simplicity, type safety, and rapid development of RESTful APIs in Free Pascal. Key features include:

* 🚀 **Effortless Routing** – define endpoints with fully typed parameters for consistent and clear API behavior.
* ✅ **Strict Type Safety** – request parameters are automatically validated and converted (`string`, `integer`, `float`, `boolean`).
* 🛡️ **Robust Error Handling** – invalid or missing parameters are rejected with clear, structured JSON error messages.
* 📖 **Automatic API Documentation** – OpenAPI specification is generated automatically and accessible at `/openapi.json`.
* 🎨 **Interactive Swagger Interface** – explore, test, and document your API interactively via `/docs`.
* ⚡ **Lightweight & High Performance** – optimized for speed and efficiency using native Free Pascal code.
* 🏗️ **Standalone Web Server** – runs independently with no external server dependencies.
* 🔧 **Developer-Friendly** – minimal boilerplate required to get your API up and running.

PhotonAPI is ideal for developers who want a fast, type-safe, and self-contained API framework without sacrificing flexibility or maintainability.


## Installation

PhotonAPI is available through [**Nova Packager**](https://github.com/daar/nova) for easy integration into your projects. To install, run the following command in your project directory:

```bash
nova require daar/photonapi
```

This will automatically download PhotonAPI and make it available for use in your Free Pascal project.


## Quick Start

### 1. Define Routes with Typed Parameters

Create a new Free Pascal program using `PhotonAPI`:

```pascal
program MyAPI;

uses
  PhotonAPI, SysUtils;

procedure GreetHandler(aReq: TRequest; aResp: TResponse; const Args: array of variant);
begin
  // Args[] are fully typed based on the route declaration
  SendResponse(aResp, [
    'message', 'Hello, ' + Args[0],
    'age', Args[1],
    'premium', Args[2]
  ]);
end;

begin
  // Register a GET route with typed query parameters
  RegisterRoute('/greet', 'GET', @GreetHandler, [
    Param('name', ptString, 'Anonymous'),
    Param('age', ptInteger, 0),
    Param('premium', ptBoolean, False)
  ]);

  // Start the web server
  Application.Run;
end.
```

### 2. Start the Server

Compile and run your program:

```bash
fpc myapi.pas
./myapi
```

The server will run at **[http://localhost:8080](http://localhost:8080)**.

### 3. Test Your API

Access your typed route using query parameters:

```http
GET http://localhost:8080/greet?name=Alice&age=30&premium=true
```

**Response:**

```json
{
  "status": "success",
  "data": {
    "message": "Hello, Alice",
    "age": 30,
    "premium": true
  }
}
```

Explore OpenAPI and Swagger UI:

* **OpenAPI JSON:** [http://localhost:8080/openapi.json](http://localhost:8080/openapi.json)
* **Swagger UI:** [http://localhost:8080/docs](http://localhost:8080/docs)


## Project Status

Contributions, feature requests, and feedback are always welcome. Please submit issues via the [issue tracker](https://github.com/daar/photonapi/issues) or contribute improvements through pull requests.



## License

PhotonAPI is released under the **MIT License**.
You are free to use it in both commercial and open-source projects.