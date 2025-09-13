program example;

{$mode objfpc}{$H+}

uses
  {$ifdef UNIX}cthreads, cmem,{$endif}
  fphttpapp,
  httpdefs,
  CometAPI;

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
    name := Args[0];      // string
    age := Args[1];       // integer
    premium := Args[2];   // boolean

    SendResponse(aResp, [
      'message', 'Hello from Route 2',
      'name', name,
      'age', age,
      'premium', premium
    ]);
  end;

begin
  // Override the default application title for your application
  Application.Title := 'CometAPI Demo';

  // Register user routes (system routes are hidden in the unit)
  RegisterRoute('/', 'GET', @Route1, []);

  RegisterRoute('/route2', 'GET', @Route2, [
    Param('name', ptString, 'Anonymous'),
    Param('age', ptInteger, 18),
    Param('premium', ptBoolean, False)
  ]);

  Application.Run;
end.
