unit PhotonAPI;

{$mode objfpc}{$H+}

interface

uses
  Classes, fphttpapp, fpjson, httpdefs, httproute, jsonparser, SysUtils,
  Variants, Middleware;

type
  TParamType = (ptString, ptInteger, ptFloat, ptBoolean);

  TRouteParam = record
    name: string;
    ParamType: TParamType;
    DefaultValue: variant;
  end;

  TRouteHandler = procedure(aReq: TRequest; aResp: TResponse;
    const Args: array of variant);

  TRouteInfo = record
    Path: string;
    Method: string;
    Params: array of TRouteParam;
    Callback: TRouteHandler;
    IsSystem: boolean;
  end;

var
  Routes: array of TRouteInfo;

function Param(const name: string; ParamType: TParamType; Default: variant): TRouteParam;

procedure RegisterRoute(const Path, Method: string; Callback: TRouteHandler;
  const Params: array of TRouteParam; IsDefault: boolean = False);

procedure SendResponse(aResp: TResponse; const Pairs: array of const);

procedure Use(const PathMask: string; MiddlewareProc: TMiddleware);

implementation

// ------------ Param helpers ------------
function Param(const name: string; ParamType: TParamType; Default: variant): TRouteParam;
begin
  Result.name := name;
  Result.ParamType := ParamType;
  Result.DefaultValue := Default;
end;

function ParamTypeToString(pt: TParamType): string;
begin
  case pt of
    ptString: Result := 'string';
    ptInteger: Result := 'integer';
    ptFloat: Result := 'number';
    ptBoolean: Result := 'boolean';
    else
      Result := 'string';
  end;
end;

function GetParamValue(aReq: TRequest; Param: TRouteParam;
  out ErrorMsg: string): variant;
var
  raw: string;
begin
  raw := aReq.QueryFields.Values[Param.name];
  ErrorMsg := '';

  if raw = '' then
  begin
    Result := Param.DefaultValue;
    exit;
  end;

  try
    case Param.ParamType of
      ptString: Result := raw;
      ptInteger: Result := StrToInt(raw);
      ptFloat: Result := StrToFloat(raw);
      ptBoolean: Result := (LowerCase(raw) = 'true') or (raw = '1') or (raw = 'yes');
      else
        Result := Param.DefaultValue;
    end;
  except
    on E: Exception do
    begin
      Result := Null;
      ErrorMsg := Format('Invalid type for parameter "%s": expected %s, got "%s"',
        [Param.name, ParamTypeToString(Param.ParamType), raw]);
    end;
  end;
end;

// ------------ Middleware helper ------------

procedure Use(const PathMask: string; MiddlewareProc: TMiddleware);
var
  idx: Integer;
begin
  idx := Length(Middlewares);
  SetLength(Middlewares, idx+1);
  Middlewares[idx].PathMask := PathMask;
  Middlewares[idx].Proc := MiddlewareProc;
end;

// ------------ Response helper ------------
procedure SendResponse(aResp: TResponse; const Pairs: array of const);
var
  dataObj, wrapper: TJSONObject;
  i: integer;
  key: string;
begin
  dataObj := TJSONObject.Create;
  try
    i := 0;
    while i < Length(Pairs) do
    begin
      if i + 1 >= Length(Pairs) then Break;

      // Get key
      case Pairs[i].VType of
        vtAnsiString: key := string(Pairs[i].VAnsiString);
        vtUnicodeString: key := string(Pairs[i].VUnicodeString);
        vtString: key := string(Pairs[i].VString^);
        vtVariant: key := VarToStr(Pairs[i].VVariant^);
      else
        key := VarToStr(Pairs[i].VVariant^);
      end;

      // Add value
      case Pairs[i+1].VType of
        vtAnsiString:   dataObj.Add(key, string(Pairs[i+1].VAnsiString));
        vtUnicodeString:dataObj.Add(key, string(Pairs[i+1].VUnicodeString));
        vtString:       dataObj.Add(key, string(Pairs[i+1].VString^));
        vtInteger:      dataObj.Add(key, Pairs[i+1].VInteger);
        vtBoolean:      dataObj.Add(key, Pairs[i+1].VBoolean);
        vtExtended:     dataObj.Add(key, Pairs[i+1].VExtended^);
        vtVariant:
          case TVarData(Pairs[i+1].VVariant^).VType of
            varNull:    dataObj.Add(key, Null);
            varInteger, varSmallint, varShortInt,
            varByte, varWord, varLongWord, varInt64:
                        dataObj.Add(key, Integer(Pairs[i+1].VVariant^));
            varSingle, varDouble, varCurrency:
                        dataObj.Add(key, Double(Pairs[i+1].VVariant^));
            varBoolean: dataObj.Add(key, Boolean(Pairs[i+1].VVariant^));
            varUString, varString, varOleStr:
                        dataObj.Add(key, VarToStr(Pairs[i+1].VVariant^));
          else
            dataObj.Add(key, VarToStr(Pairs[i+1].VVariant^));
          end;
      else
        dataObj.Add(key, VarToStr(Pairs[i+1].VVariant^));
      end;

      Inc(i, 2);
    end;

    wrapper := TJSONObject.Create;
    try
      wrapper.Add('status', 'success');
      wrapper.Add('data', dataObj.Clone);
      aResp.ContentType := 'application/json';
      aResp.Content := wrapper.AsJSON;
    finally
      wrapper.Free;
    end;
  finally
    dataObj.Free;
  end;
end;

procedure SendServerResponse(aResp: TResponse; const code: word; msg: string = '');
begin
  aResp.ContentType := 'application/json';

  // Provide default messages if msg is empty
  if msg = '' then
    case code of
      100: msg := '{"info":"Continue"}';
      101: msg := '{"info":"Switching Protocols"}';
      102: msg := '{"info":"Processing"}';
      200: msg := '{"success":"OK"}';
      201: msg := '{"success":"Created"}';
      202: msg := '{"success":"Accepted"}';
      203: msg := '{"success":"Non-Authoritative Information"}';
      204: msg := '{"success":"No Content"}';
      205: msg := '{"success":"Reset Content"}';
      206: msg := '{"success":"Partial Content"}';
      207: msg := '{"success":"Multi-Status"}';
      208: msg := '{"success":"Already Reported"}';
      226: msg := '{"success":"IM Used"}';
      300: msg := '{"error":"Multiple Choices"}';
      301: msg := '{"error":"Moved Permanently"}';
      302: msg := '{"error":"Found"}';
      303: msg := '{"error":"See Other"}';
      304: msg := '{"error":"Not Modified"}';
      305: msg := '{"error":"Use Proxy"}';
      307: msg := '{"error":"Temporary Redirect"}';
      308: msg := '{"error":"Permanent Redirect"}';
      400: msg := '{"error":"Bad Request"}';
      401: msg := '{"error":"Unauthorized"}';
      402: msg := '{"error":"Payment Required"}';
      403: msg := '{"error":"Forbidden"}';
      404: msg := '{"error":"Not Found"}';
      405: msg := '{"error":"Method Not Allowed"}';
      406: msg := '{"error":"Not Acceptable"}';
      407: msg := '{"error":"Proxy Authentication Required"}';
      408: msg := '{"error":"Request Timeout"}';
      409: msg := '{"error":"Conflict"}';
      410: msg := '{"error":"Gone"}';
      411: msg := '{"error":"Length Required"}';
      412: msg := '{"error":"Precondition Failed"}';
      413: msg := '{"error":"Payload Too Large"}';
      414: msg := '{"error":"URI Too Long"}';
      415: msg := '{"error":"Unsupported Media Type"}';
      416: msg := '{"error":"Range Not Satisfiable"}';
      417: msg := '{"error":"Expectation Failed"}';
      418: msg := '{"error":"I''m a teapot"}';
      421: msg := '{"error":"Misdirected Request"}';
      422: msg := '{"error":"Unprocessable Entity"}';
      423: msg := '{"error":"Locked"}';
      424: msg := '{"error":"Failed Dependency"}';
      425: msg := '{"error":"Too Early"}';
      426: msg := '{"error":"Upgrade Required"}';
      428: msg := '{"error":"Precondition Required"}';
      429: msg := '{"error":"Too Many Requests"}';
      431: msg := '{"error":"Request Header Fields Too Large"}';
      451: msg := '{"error":"Unavailable For Legal Reasons"}';
      500: msg := '{"error":"Internal Server Error"}';
      501: msg := '{"error":"Not Implemented"}';
      502: msg := '{"error":"Bad Gateway"}';
      503: msg := '{"error":"Service Unavailable"}';
      504: msg := '{"error":"Gateway Timeout"}';
      505: msg := '{"error":"HTTP Version Not Supported"}';
      506: msg := '{"error":"Variant Also Negotiates"}';
      507: msg := '{"error":"Insufficient Storage"}';
      508: msg := '{"error":"Loop Detected"}';
      510: msg := '{"error":"Not Extended"}';
      511: msg := '{"error":"Network Authentication Required"}';
    else
      msg := Format('{"error":"Unknown status %d"}', [code]);
    end;

  aResp.Code := code;
  aResp.Content := msg;
end;


// ------------ Dispatcher ------------
procedure GlobalDispatcher(aReq: TRequest; aResp: TResponse);
var
  i, j: integer;
  values: array of variant;
  reqPath: string;
  errMsg: string;
  jsonData: TJSONData;
  bodyObj: TJSONObject;
  mw: TMiddlewareEntry;
  code: word;

  function RouteParamExists(const Params: array of TRouteParam; const Name: string): Boolean;
  var
    k: Integer;
  begin
    Result := False;
    for k := 0 to High(Params) do
      if SameText(Params[k].Name, Name) then
        exit(True);
  end;

begin
  //execute middleware
  for mw in Middlewares do
    if PathMatches(mw.PathMask, aReq.URI) then
    begin
      code := mw.Proc(aReq, aResp);
      if (code >= 400) and (code <= 599) then
      begin
        SendServerResponse(aResp, code);
        exit;
      end;
    end;

  reqPath := StripQuery(aReq.URI);

  for i := 0 to High(Routes) do
  begin
    if (CompareText(Routes[i].Path, reqPath) = 0) and
       (CompareText(Routes[i].Method, aReq.Method) = 0) then
    begin
      SetLength(values, Length(Routes[i].Params));

      if SameText(Routes[i].Method, 'POST') then
      begin
        // Parse JSON body
        try
          jsonData := GetJSON(aReq.Content);
        except
          on E: Exception do
          begin
            aResp.Code := 400;
            aResp.Content := '{"error":"Invalid JSON"}';
            exit;
          end;
        end;

        if not (jsonData is TJSONObject) then
        begin
          aResp.Code := 400;
          aResp.Content := '{"error":"Expected JSON object in body"}';
          jsonData.Free;
          exit;
        end;

        bodyObj := TJSONObject(jsonData);
        try
          // Reject unknown fields
          for j := 0 to bodyObj.Count - 1 do
            if not RouteParamExists(Routes[i].Params, bodyObj.Names[j]) then
            begin
              aResp.Code := 400;
              aResp.Content := '{"error":"Unknown field: ' + bodyObj.Names[j] + '"}';
              exit;
            end;

          // Validate required fields and type parameters
          for j := 0 to High(Routes[i].Params) do
          begin
            if bodyObj.Find(Routes[i].Params[j].Name) = nil then
            begin
              aResp.Code := 400;
              aResp.Content := '{"error":"Missing required field: ' + Routes[i].Params[j].Name + '"}';
              exit;
            end;

            case Routes[i].Params[j].ParamType of
              ptString:  values[j] := bodyObj.Get(Routes[i].Params[j].Name,
                                 VarToStr(Routes[i].Params[j].DefaultValue));
              ptInteger: values[j] := bodyObj.Get(Routes[i].Params[j].Name,
                                 Integer(Routes[i].Params[j].DefaultValue));
              ptFloat:   values[j] := bodyObj.Get(Routes[i].Params[j].Name,
                                 Double(Routes[i].Params[j].DefaultValue));
              ptBoolean: values[j] := bodyObj.Get(Routes[i].Params[j].Name,
                                 Boolean(Routes[i].Params[j].DefaultValue));
            else
              values[j] := Routes[i].Params[j].DefaultValue;
            end;
          end;
        finally
          bodyObj.Free;
        end;
      end
      else
      begin
        // GET / query parameters
        for j := 0 to High(Routes[i].Params) do
        begin
          values[j] := GetParamValue(aReq, Routes[i].Params[j], errMsg);
          if errMsg <> '' then
          begin
            aResp.Code := 400;
            aResp.Content := '{"error":"' + errMsg + '"}';
            exit;
          end;
        end;
      end;

      // Call the handler with fully typed Args[]
      if Assigned(Routes[i].Callback) then
        Routes[i].Callback(aReq, aResp, values);

      exit;
    end;
  end;

  // Route not found
  aResp.Code := 404;
  aResp.Content := '{"error":"Not Found"}';
end;

// ------------ Register route ------------
procedure RegisterRoute(const Path, Method: string; Callback: TRouteHandler;
  const Params: array of TRouteParam; IsDefault: boolean = False);
var
  idx, i: integer;
begin
  idx := Length(Routes);
  SetLength(Routes, idx + 1);

  Routes[idx].Path := Path;
  Routes[idx].Method := UpperCase(Method);

  // If POST and no Params are declared, still create empty array
  if (UpperCase(Method) = 'POST') and (Length(Params) = 0) then
    SetLength(Routes[idx].Params, 0)
  else
    SetLength(Routes[idx].Params, Length(Params));

  for i := 0 to High(Params) do
    Routes[idx].Params[i] := Params[i];

  Routes[idx].Callback := Callback;
  Routes[idx].IsSystem := False;

  HTTPRouter.RegisterRoute(Path, @GlobalDispatcher, IsDefault);
end;


// ------------ System routes ------------
procedure OpenAPIHandler(aReq: TRequest; aResp: TResponse; const Args: array of variant);
var
  rootObj, infoObj, pathsObj, pathObj, methodObj, responsesObj, paramObj, requestBodyObj, contentObj, schemaObj, propsObj: TJSONObject;
  paramsArr, requiredArr: TJSONArray;
  i, j: integer;
begin
  rootObj := TJSONObject.Create;
  try
    // OpenAPI header
    rootObj.Add('openapi', '3.0.0');

    // Info
    infoObj := TJSONObject.Create;
    infoObj.Add('title', Application.Title);
    infoObj.Add('version', '1.0');
    rootObj.Add('info', infoObj);

    pathsObj := TJSONObject.Create;

    // loop through user routes
    for i := 0 to High(Routes) do
    begin
      if Routes[i].IsSystem then
        Continue; // hide system routes

      pathObj := TJSONObject.Create;
      methodObj := TJSONObject.Create;

      // Responses
      responsesObj := TJSONObject.Create;
      responsesObj.Add('200', TJSONObject.Create(['description', 'OK']));
      methodObj.Add('responses', responsesObj);

      if SameText(Routes[i].Method, 'POST') then
      begin
        // POST requestBody with required fields
        propsObj := TJSONObject.Create;
        for j := 0 to High(Routes[i].Params) do
        begin
          propsObj.Add(Routes[i].Params[j].Name,
            TJSONObject.Create(['type', ParamTypeToString(Routes[i].Params[j].ParamType)]));
        end;

        schemaObj := TJSONObject.Create;
        schemaObj.Add('type', 'object');
        schemaObj.Add('properties', propsObj);

        // Required array
        requiredArr := TJSONArray.Create;
        for j := 0 to High(Routes[i].Params) do
          requiredArr.Add(Routes[i].Params[j].Name);
        schemaObj.Add('required', requiredArr);

        contentObj := TJSONObject.Create;
        contentObj.Add('application/json', 
          TJSONObject.Create(['schema', schemaObj]));

        requestBodyObj := TJSONObject.Create;
        requestBodyObj.Add('required', True);
        requestBodyObj.Add('content', contentObj);

        methodObj.Add('requestBody', requestBodyObj);
      end
      else
      begin
        // GET query parameters
        paramsArr := TJSONArray.Create;
        for j := 0 to High(Routes[i].Params) do
        begin
          paramObj := TJSONObject.Create;
          paramObj.Add('name', Routes[i].Params[j].Name);
          paramObj.Add('in', 'query');
          paramObj.Add('required', True); // required query parameters
          paramObj.Add('schema', 
            TJSONObject.Create(['type', ParamTypeToString(Routes[i].Params[j].ParamType)]));
          paramsArr.Add(paramObj);
        end;
        methodObj.Add('parameters', paramsArr);
      end;

      // attach method to path
      pathObj.Add(LowerCase(Routes[i].Method), methodObj);
      pathsObj.Add(Routes[i].Path, pathObj);
    end;

    rootObj.Add('paths', pathsObj);

    // return JSON
    aResp.ContentType := 'application/json';
    aResp.Content := rootObj.FormatJSON;
  finally
    rootObj.Free;
  end;
end;

procedure DocsHandler(aReq: TRequest; aResp: TResponse; const Args: array of variant);
begin
  aResp.ContentType := 'text/html';
  aResp.Content :=
    '<!DOCTYPE html>' +
    '<html lang="en">' +
    '<head>' +
    '  <meta charset="UTF-8">' +
    '  <meta name="viewport" content="width=device-width, initial-scale=1.0">' +
    '  <title>' + Application.Title + ' - API Docs</title>' +
    '  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@4/swagger-ui.css">' +
    '</head>' +
    '<body>' +
    '  <div id="swagger-ui"></div>' +
    '  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@4/swagger-ui-bundle.js"></script>' +
    '  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@4/swagger-ui-standalone-preset.js"></script>' +
    '  <script>' +
    '    window.onload = function() {' +
    '      SwaggerUIBundle({' +
    '        url: "/openapi.json",' +
    '        dom_id: "#swagger-ui",' +
    '        deepLinking: true,' +
    '        presets: [' +
    '          SwaggerUIBundle.presets.apis,' +
    '          SwaggerUIStandalonePreset' +
    '        ],' +
    '        showTopbar: false' +       // <-- hide topbar
    '      });' +
    '    };' +
    '  </script>' +
    '</body>' +
    '</html>';
end;

initialization
  // Register system/internal routes automatically
  RegisterRoute('/openapi.json', 'GET', @OpenAPIHandler, [], False);
  Routes[High(Routes)].IsSystem := True;

  RegisterRoute('/docs', 'GET', @DocsHandler, [], False);
  Routes[High(Routes)].IsSystem := True;

  // Registery system/internal middleware
  Use('/route2', @HeaderMiddleware);

  Application.Title := 'PhotonAPI';
  Application.Port := 8080;
  Application.Threaded := True;
  Application.Initialize;
end.
