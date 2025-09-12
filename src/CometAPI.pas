unit CometAPI;

{$mode objfpc}{$H+}

interface

uses
  Classes, fphttpapp, fpjson, httpdefs, httproute, SysUtils;

type
  TRouteInfo = record
    Path: string;
    Method: string;
    IsSystem: boolean; // mark system/internal routes
  end;

var
  Routes: array of TRouteInfo;

// Registers a user route (the system routes are hidden)
procedure RegisterRoute(const Path, Method: string; Callback: TRouteCallback;
  IsDefault: boolean = False);
procedure JsonResponse(aResp: TResponse; Data: TJSONObject);

implementation

// -------------------- Route registration --------------------
procedure InternalRegisterRoute(const Path, Method: string;
  Callback: TRouteCallback; IsDefault: boolean; IsSystem: boolean);
var
  idx: integer;
begin
  HTTPRouter.RegisterRoute(Path, Callback, IsDefault);
  idx := Length(Routes);
  SetLength(Routes, idx + 1);
  Routes[idx].Path := Path;
  Routes[idx].Method := UpperCase(Method);
  Routes[idx].IsSystem := IsSystem;
end;

procedure RegisterRoute(const Path, Method: string; Callback: TRouteCallback;
  IsDefault: boolean = False);
begin
  InternalRegisterRoute(Path, Method, Callback, IsDefault, False);
end;

// -------------------- JSON response wrapper --------------------
procedure JsonResponse(aResp: TResponse; Data: TJSONObject);
var
  wrapper: TJSONObject;
begin
  wrapper := TJSONObject.Create;
  try
    wrapper.Add('status', 'success');
    wrapper.Add('data', Data.Clone);
    aResp.ContentType := 'application/json';
    aResp.Content := wrapper.AsJSON;
  finally
    wrapper.Free;
  end;
end;

// -------------------- OpenAPI generator --------------------
procedure ServeOpenAPI(aReq: TRequest; aResp: TResponse);
var
  rootObj, pathsObj, methodObj, respObj: TJSONObject;
  i: integer;
begin
  if aReq.Method = 'OPTIONS' then
  begin
    aResp.Code := 204;
    aResp.SetCustomHeader('Access-Control-Allow-Origin', '*');
    aResp.SetCustomHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    aResp.SetCustomHeader('Access-Control-Allow-Headers', '*');
    Exit;
  end;

  if aReq.Method <> 'GET' then
  begin
    aResp.Code := 405;
    aResp.Content := '{"error":"Method not allowed"}';
    Exit;
  end;

  rootObj := TJSONObject.Create;
  try
    rootObj.Add('openapi', '3.0.0');
    rootObj.Add('info', TJSONObject.Create(['title', Application.Title, 'version', '1.0']));
    pathsObj := TJSONObject.Create;

    for i := 0 to High(Routes) do
    begin
      if Routes[i].IsSystem then
        Continue;  // skip system/internal routes in OpenAPI paths

      methodObj := TJSONObject.Create;
      respObj := TJSONObject.Create;
      respObj.Add('200', TJSONObject.Create(['description', 'OK']));
      methodObj.Add(LowerCase(Routes[i].Method),
        TJSONObject.Create(['responses', respObj]));
      pathsObj.Add(Routes[i].Path, methodObj);
    end;

    rootObj.Add('paths', pathsObj);
    aResp.ContentType := 'application/json';
    aResp.SetCustomHeader('Access-Control-Allow-Origin', '*');
    aResp.Content := rootObj.FormatJSON;
  finally
    rootObj.Free;
  end;
end;

// -------------------- Docs UI (Swagger) --------------------
procedure ServeDocs(aReq: TRequest; aResp: TResponse);
begin
  aResp.ContentType := 'text/html';
  aResp.Content :=
    '<!DOCTYPE html>' + '<html lang="en">' + '<head>' +
    '<meta charset="UTF-8">' + '<title>' + Application.Title + '</title>' +
    '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@4/swagger-ui.css">'
    + '</head>' + '<body>' + '<div id="swagger-ui"></div>' +
    '<script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@4/swagger-ui-bundle.js"></script>'
    + '<script>' + 'const ui = SwaggerUIBundle({' + '  url: "/openapi.json",' +
    '  dom_id: "#swagger-ui"' + '});' + '</script>' + '</body>' + '</html>';
end;

// -------------------- Initialization --------------------
initialization
  // Register system/internal routes automatically, hidden from user
  InternalRegisterRoute('/openapi.json', 'GET', @ServeOpenAPI, False, True);
  InternalRegisterRoute('/docs', 'GET', @ServeDocs, True, True);

  Application.Title := 'CometAPI';
  Application.Port := 8080;
  Application.Threaded := True;
  Application.Initialize;
end.
