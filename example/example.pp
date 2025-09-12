program example;

{$mode objfpc}{$H+}

uses
  {$ifdef UNIX}cthreads, cmem,{$endif}
  Classes,
  CometAPI,
  fphttpapp,
  fpjson,
  httpdefs,
  SysUtils;

  procedure Route1(aReq: TRequest; aResp: TResponse);
  var
    Data: TJSONObject;
  begin
    if aReq.Method <> 'GET' then
    begin
      aResp.Code := 405;
      aResp.Content := '{"error":"Method not allowed"}';
      Exit;
    end;

    Data := TJSONObject.Create;
    try
      Data.Add('message', 'Hello from Route 1');
      JsonResponse(aResp, Data);
    finally
      Data.Free;
    end;
  end;

  procedure Route2(aReq: TRequest; aResp: TResponse);
  var
    Data:      TJSONObject;
    nameParam: string;
  begin
    if aReq.Method <> 'GET' then
    begin
      aResp.Code := 405;
      aResp.Content := '{"error":"Method not allowed"}';
      Exit;
    end;

    nameParam := aReq.QueryFields.Values['name'];
    if nameParam = '' then
      nameParam := 'Anonymous';

    Data := TJSONObject.Create;
    try
      Data.Add('message', 'Hello from Route 2');
      Data.Add('name', nameParam);
      JsonResponse(aResp, Data);
    finally
      Data.Free;
    end;
  end;

begin
  Application.Title := 'CometAPI Demo';

  // Register user routes (system routes are hidden in the unit)
  RegisterRoute('/', 'GET', @Route1);
  RegisterRoute('/route2', 'GET', @Route2);

  Application.Run;
end.
