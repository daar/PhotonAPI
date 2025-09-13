unit CometAPI;

{$mode objfpc}{$H+}

interface

uses
  Classes, fphttpapp, fpjson, httpdefs, httproute, jsonparser, SysUtils,
  Variants;

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

// ------------ Dispatcher ------------
function StripQuery(const URI: string): string;
var
  posQ: integer;
begin
  posQ := Pos('?', URI);
  if posQ > 0 then
    Result := Copy(URI, 1, posQ - 1)
  else
    Result := URI;
end;

procedure GlobalDispatcher(aReq: TRequest; aResp: TResponse);
var
  i, j: integer;
  values: array of variant;
  reqPath: string;
  errMsg: string;
  jsonData: TJSONData;
  bodyObj: TJSONObject;

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

  Application.Title := 'CometAPI';
  Application.Port := 8080;
  Application.Threaded := True;
  Application.Initialize;
end.
