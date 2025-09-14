program example;

{$mode objfpc}{$H+}

uses
  {$ifdef UNIX}cthreads, cmem,{$endif}
  Classes,
  PhotonAPI,
  fphttpapp,
  fpjson,
  httpdefs,
  SysUtils;

  procedure Route1(aReq: TRequest; aResp: TResponse; const Args: array of variant);
  begin
    SendResponse(aResp, [
      'message', 'Hello from Route 1'
    ]);
  end;

  procedure Route2(aReq: TRequest; aResp: TResponse; const Args: array of variant);
  var
    name:    string;
    age:     integer;
    premium: boolean;
  begin
    // Args[0] = name (string)
    // Args[1] = age (integer)
    // Args[2] = premium (boolean)

    SendResponse(aResp, [
      'message', 'Hello from Route 2',
      'name', Args[0],
      'age', Args[1],
      'premium', Args[2]
    ]);
  end;

  procedure PostRoute(aReq: TRequest; aResp: TResponse; const Args: array of variant);
  begin
    // Args[0] = name (string)
    // Args[1] = age (integer)
    // Args[2] = premium (boolean)

    SendResponse(aResp, [
      'name', Args[0],
      'age', Args[1],
      'premium', Args[2]
    ]);
  end;

  function HeaderMiddleware(aReq: TRequest; aResp: TResponse): word;
  begin
    //only add the header
    aResp.SetCustomHeader('X-Powered-By', 'PhotonAPI');
    exit(200);
  end;

begin
  // Override the default application title for your application
  Application.Title := 'PhotonAPI Demo';

  // Register user routes (system routes are hidden in the unit)
  RegisterRoute('/', 'GET', @Route1, [], true);

  RegisterRoute('/route2', 'GET', @Route2, [
    Param('name', ptString, 'Anonymous'),
    Param('age', ptInteger, 18),
    Param('premium', ptBoolean, False)
  ]);

  RegisterRoute('/postdemo', 'POST', @PostRoute, [
    Param('name', ptString, 'Anonymous'),
    Param('age', ptInteger, 0),
    Param('premium', ptBoolean, False)
  ]);

  // Add custom middleware
  Use('/route2', @HeaderMiddleware);

  Application.Run;
end.
