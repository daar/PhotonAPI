unit Middleware;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  httpdefs;

type
  TMiddleware = function(aReq: TRequest; aResp: TResponse): word;

  TMiddlewareEntry = record
    PathMask: string;   // e.g. "*" or "/users/*" or "/admin"
    Proc: TMiddleware;
  end;

function PathMatches(const aPathMask, aURI: string): boolean;
function StripQuery(const URI: string): string;

var
  Middlewares: array of TMiddlewareEntry;

implementation

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

function PathMatches(const aPathMask, aURI: string): boolean;
var
  URI: String;
begin
  URI := StripQuery(aURI);

  // Global match: "*"
  if aPathMask = '*' then
    Exit(True);

  // Prefix match for masks ending with "/*"
  if Copy(aPathMask, Length(aPathMask)-1+1, 2) = '/*' then
    exit(Copy(URI, 1, Length(aPathMask)-2) = Copy(aPathMask, 1, Length(aPathMask)-2));

  // Exact match
  Result := aPathMask = URI;
end;

end.
