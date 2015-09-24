{******************************************************************************}
{                       CnPack For Delphi/C++Builder                           }
{                     中国人自己的开放源码第三方开发包                         }
{                   (C)Copyright 2001-2015 CnPack 开发组                       }
{                   ------------------------------------                       }
{                                                                              }
{            本开发包是开源的自由软件，您可以遵照 CnPack 的发布协议来修        }
{        改和重新发布这一程序。                                                }
{                                                                              }
{            发布这一开发包的目的是希望它有用，但没有任何担保。甚至没有        }
{        适合特定目的而隐含的担保。更详细的情况请参阅 CnPack 发布协议。        }
{                                                                              }
{            您应该已经和开发包一起收到一份 CnPack 发布协议的副本。如果        }
{        还没有，可访问我们的网站：                                            }
{                                                                              }
{            网站地址：http://www.cnpack.org                                   }
{            电子邮件：master@cnpack.org                                       }
{                                                                              }
{******************************************************************************}

unit CnEventBus;
{* |<PRE>
================================================================================
* 软件名称：CnPack
* 单元名称：CnEventBus 实现单元
* 单元作者：Liu Xiao
* 备    注：该单元为 CnEventBus 的实现单元，模拟一个简单的 EventBus，实现低耦合度
*           的通知器注册以及通知发送，暂无线程控制等机制。
*           事件以字符串类型的名字区分。
* 开发平台：PWin2000Pro + Delphi 5.01
* 兼容测试：PWin9X/2000/XP + Delphi 5/6/7 + C++Builder 5/6
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 单元标识：$Id$
* 修改记录：2015.09.24 V1.0
*               创建单元
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Windows, Messages, Classes, CnHashMap;

type
  ECnEventBusException = class(Exception);

  ICnEvent = interface
  {* 事件接口}
  ['{766BAE68-ABDA-4DE2-A76A-130FA78978D3}']
    function GetEventName: string;
    procedure SetEventName(const AEventName: string);
    function GetEventData: Pointer;
    procedure SetEventData(AEventData: Pointer);

    property EventName: string read GetEventName write SetEventName;
    {* 事件名称}
    property EventData: Pointer read GetEventData write SetEventData;
    {* 事件携带的数据}
  end;

  TCnEvent = class(TInterfacedObject, ICnEvent)
  {* 事件的实现类}
  private
    FEventName: string;
    FEventData: Pointer;
  public
    constructor Create(const AEventName: string; AEventData: Pointer = nil);
    destructor Destroy; override;
    
    function GetEventName: string;
    procedure SetEventName(const AEventName: string);
    function GetEventData: Pointer;
    procedure SetEventData(AEventData: Pointer);

    property EventName: string read GetEventName write SetEventName;
    property EventData: Pointer read GetEventData write SetEventData;
  end;

  ICnEventBusReceiver = interface
  {* 通知接收器接口}
  ['{F03E825C-FD29-4AD8-B48E-D3BBF1DDE045}']
    procedure OnEvent(Event: ICnEvent);
    {* 发生事件通知时调用}
  end;

  TCnEventBus = class(TObject)
  {* EventBus 通知注册与分发的实现类}
  private
    FReceivers: TCnStrToPtrHashMap;
    FSynchronizer: TMultiReadExclusiveWriteSynchronizer;
    procedure FreeReceiverSlots;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterReceiver(Receiver: ICnEventBusReceiver); overload;
    {* 注册一个通知接收器，接收所有事件通知}
    procedure RegisterReceiver(Receiver: ICnEventBusReceiver; EventName: string); overload;
    {* 注册一个通知接收器，接收一特定的字符串事件名通知，不支持通配符}
    procedure RegisterReceiver(Receiver: ICnEventBusReceiver; EventNames: array of const); overload;
    {* 注册一个通知接收器，接收匹配特定一批字符串事件名的通知，不支持通配符}

    procedure UnRegisterReceiver(Receiver: ICnEventBusReceiver);
    {* 取消注册一个通知接收器}

    procedure PostEvent(Event: ICnEvent); overload;
    {* 触发一个事件，参数为事件实例}
    procedure PostEvent(const EventName: string); overload;
    {* 触发一个事件，参数为事件名，事件实例将在内部创建}
    procedure PostEvent(const EventName: string; EventData: Pointer); overload;
    {* 触发一个事件，参数为事件名与数据，事件实例将在内部创建}
  end;

function EventBus: TCnEventBus;
{* 获得全局 EventBus 对象}

implementation

const
  ANY_EVENT = '*';

type
  NoRef = Pointer;

var
  FEventBus: TCnEventBus = nil;

function EventBus: TCnEventBus;
begin
  if FEventBus = nil then
    FEventBus := TCnEventBus.Create;
  Result := FEventBus;
end;

{ TCnEvent }

constructor TCnEvent.Create(const AEventName: string; AEventData: Pointer);
begin
  inherited Create;
  FEventName := AEventName;
  FEventData := AEventData;
end;

destructor TCnEvent.Destroy;
begin

  inherited;
end;

function TCnEvent.GetEventData: Pointer;
begin
  Result := FEventData;
end;

function TCnEvent.GetEventName: string;
begin
  Result := FEventName;
end;

procedure TCnEvent.SetEventData(AEventData: Pointer);
begin
  FEventData := AEventData;
end;

procedure TCnEvent.SetEventName(const AEventName: string);
begin
  FEventName := AEventName;
end;

{ TCnEventBus }

constructor TCnEventBus.Create;
begin
  inherited;
  FReceivers := TCnStrToPtrHashMap.Create;
  FSynchronizer := TMultiReadExclusiveWriteSynchronizer.Create;
end;

destructor TCnEventBus.Destroy;
begin
  FreeReceiverSlots;
  FReceivers.Free;
  FSynchronizer.Free;
  inherited;
end;

procedure TCnEventBus.PostEvent(Event: ICnEvent);
var
  I: Integer;
  List: Pointer;
begin
  if Event = nil then
    Exit;

  if FReceivers.Find(ANY_EVENT, List) then
  begin
    for I := 0 to TList(List).Count - 1 do
    try
      ICnEventBusReceiver(TList(List)[I]).OnEvent(Event);
    except
      ;
    end;
  end;

  if (Event.EventName <> ANY_EVENT) and FReceivers.Find(Event.EventName, List) then
  begin
    for I := 0 to TList(List).Count - 1 do
    try
      ICnEventBusReceiver(TList(List)[I]).OnEvent(Event);
    except
      ;
    end;
  end;
end;

procedure TCnEventBus.FreeReceiverSlots;
var
  Key: string;
  List: Pointer;
begin
  FSynchronizer.BeginWrite;

  FReceivers.StartEnum;
  while FReceivers.GetNext(Key, List) do
    TList(List).Free;

  FSynchronizer.EndWrite;
end;

procedure TCnEventBus.PostEvent(const EventName: string; EventData: Pointer);
begin
  PostEvent(TCnEvent.Create(EventName, EventData));
end;

procedure TCnEventBus.PostEvent(const EventName: string);
begin
  PostEvent(TCnEvent.Create(EventName));
end;

procedure TCnEventBus.RegisterReceiver(Receiver: ICnEventBusReceiver);
begin
  RegisterReceiver(Receiver, ANY_EVENT);
end;

procedure TCnEventBus.RegisterReceiver(Receiver: ICnEventBusReceiver;
  EventNames: array of const);
var
  I: Integer;
begin
  for I := Low(EventNames) to High(EventNames) do
  begin
    case EventNames[I].VType of
      vtString: RegisterReceiver(Receiver, string(EventNames[I].VString^));
      vtAnsiString: RegisterReceiver(Receiver, string(AnsiString(PAnsiChar(EventNames[I].VAnsiString))));
      vtWideString: RegisterReceiver(Receiver, string(WideString(PWideChar(EventNames[I].VWideString))));
    else
      raise ECnEventBusException.Create('Invalid Event Name. Must Be String.');
    end;
  end;
end;

procedure TCnEventBus.RegisterReceiver(Receiver: ICnEventBusReceiver;
  EventName: string);
var
  List: Pointer;
begin
  FSynchronizer.BeginWrite;

  if not FReceivers.Find(EventName, List) then
  begin
    List := TList.Create;
    FReceivers.Add(EventName, List);
  end;
  TList(List).Add(NoRef(Receiver));

  FSynchronizer.EndWrite;
end;

procedure TCnEventBus.UnRegisterReceiver(Receiver: ICnEventBusReceiver);
var
  I: Integer;
  Key: string;
  List: Pointer;
begin
  FSynchronizer.BeginWrite;

  FReceivers.StartEnum;
  while FReceivers.GetNext(Key, List) do
  begin
    for I := TList(List).Count - 1 downto 0 do
      if TList(List)[I] = NoRef(Receiver) then
        TList(List).Delete(I);
  end;

  FSynchronizer.EndWrite;
end;

initialization

finalization
  FEventBus.Free;

end.
