
/// Embedded host utility library API
module dotnet.emhost;

import dotnet.helpers;

struct TypesProto
{
    extern(C) alias GetTypeFn = void* function(const(char)* reflectionTypeName);
    extern(C) alias GetMethodFn = void* function(void* type, const(char)* methodName);
    extern(C) alias GetMethodWithParamsFn = void* function(void* type, const(char)* methodName, const(char*)* params, int paramCount);
    extern(C) alias CreateInstanceFn = void* function(void* type);
    extern(C) alias ArrayCreateFn = void* function(void* type, int length);
    extern(C) alias ArrayLengthFn = int function(void* array);
    extern(C) alias ArrayGetElementFn = void* function(void* array, int index);
    extern(C) alias ArraySetElementFn = void function(void* array, int index, void* value);

    extern(C) alias GCHandleAllocFn = void* function(void* object);
    extern(C) alias GCHandleFreeFn = void function(void* object);
}

struct DelegatesProto
{
    extern(C) alias CreateForMethodFn = void* function(void* method);
    extern(C) alias ToFunctionPointerFn = void* function(void* delegate_);
    extern(C) alias DynamicInvokeFn = void* function(void* delegateHandle, void** types, void** args, int numArgs);
}

@assembly("HostSupport")
@namespace("DND.EmbedUtils.Types")
{
    TypesProto.GetTypeFn GetType;
    TypesProto.GetMethodFn GetMethod;
    TypesProto.GetMethodWithParamsFn GetMethodWithParams;
    TypesProto.CreateInstanceFn CreateInstance;
    TypesProto.ArrayCreateFn ArrayCreate;
    TypesProto.ArrayLengthFn ArrayLength;
    TypesProto.ArrayGetElementFn ArrayGetElement;
    TypesProto.ArraySetElementFn ArraySetElement;

    TypesProto.GCHandleAllocFn GCHandleAlloc;
    TypesProto.GCHandleFreeFn GCHandleFree;

}

@assembly("HostSupport")
@namespace("DND.EmbedUtils.Delegates")
{
    DelegatesProto.CreateForMethodFn CreateForMethod;
    DelegatesProto.ToFunctionPointerFn ToFunctionPointer;
    DelegatesProto.DynamicInvokeFn DynamicInvoke;
}


/// Make list of 
string[] LibsInPathShallow(const string path, const string[] extensions = [".dll"])
{
    import std.algorithm;
    import std.array;
    import std.file;
    import std.path;
    import std.string;

    return dirEntries( path.absolutePath(), SpanMode.shallow)
        .filter!(isFile)
        .filter!( a => extensions.canFind(a.name.extension.toLower))
        .map!( a => a.name )
        .array()
        ;
}


DotNetWrapper!T wrapHost(T)(T host)
{
    return DotNetWrapper!T(host);
}


struct DotNetWrapper(T)
{
    T host;

    alias host this;

    this(T host)
    {
        this.host = host;
        loadFunctions();
    }

private:
    void loadFunctions()
    {   
        GetType = host.getDelegate!GetType;
        GetMethod = host.getDelegate!GetMethod;
        GetMethodWithParams = host.getDelegate!GetMethodWithParams;
        CreateInstance = host.getDelegate!CreateInstance;
        ArrayCreate = host.getDelegate!ArrayCreate;
        ArrayLength = host.getDelegate!ArrayLength;
        ArrayGetElement = host.getDelegate!ArrayGetElement;
        ArraySetElement = host.getDelegate!ArraySetElement;

        CreateForMethod = host.getDelegate!CreateForMethod;
        ToFunctionPointer = host.getDelegate!ToFunctionPointer;
        DynamicInvoke = host.getDelegate!DynamicInvoke;
    }
}


version(unittest)
{
extern(C) alias WriteLineFn = void function(const(char)* str);
extern(C) alias ListAdd = void* function(void* list, int val);
extern(C) alias ListGetItem = int* function(void* list, int index);
}

///
unittest
{
    import std.traits;
    import std.algorithm;
    import std.array;
    import std.string;

    import dotnet.host;

    
    @assembly("netstandard")
    @namespace("System.Console")
    WriteLineFn WriteLine;
    

    auto _host = NetCoreHost.create();
    _host.initializeCLR( LibsInPathShallow(`./DotNetHostLib/build`) );

    auto host = wrapHost(_host);
    assert(host.getDelegate!GetType() !is null);



    auto listI32 = GetType("System.Collections.Generic.List`1[System.Int32]");
    auto AddMi = GetMethod(listI32, "Add");
    assert(AddMi !is null);

    string[] types = ["System.Int32"];
    auto Add1 = GetMethodWithParams(listI32, "Add", types.map!toStringz.array.ptr, 1);
    assert(Add1 !is null);

    auto clrdelegate = CreateForMethod(AddMi);
    assert(clrdelegate !is null);

    auto Add = cast(ListAdd) ToFunctionPointer(clrdelegate);
    assert(Add !is null);

    auto list = CreateInstance(listI32);
    assert(list !is null);

    //void*[2] args = [list, cast(void*) 42];
    //void*[2] argTypes = [ listI32, GetType("System.Int32") ];
    //auto r = DynamicInvoke(clrdelegate, argTypes.ptr, args.ptr, args.length);

    auto getterMi = GetMethod(listI32, "get_Item");
    auto getterDel = CreateForMethod(getterMi);
    auto Get = cast(ListGetItem) ToFunctionPointer(getterDel);

    Add(list, 42);
    assert((cast(int) Get(list, 0)) == 42);


    // full spec version (class with namespace, assembly with specific version in case there is exsisting GAC assembly)
    //auto syscon = GetType("System.Console, System.Console, Version=4.1.2.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a");
    auto con = GetType("System.Console, System.Console");
    assert(con);

    auto strType = GetType("System.String");
    assert(strType);

    auto WriteLineMi = GetMethodWithParams(con, "WriteLine", ["System.String"].map!toStringz.array.ptr, 1);
    assert(WriteLineMi);

    auto WriteLineDlg = CreateForMethod(WriteLineMi);
    assert(WriteLineDlg);

    WriteLine = cast(WriteLineFn) ToFunctionPointer(WriteLineDlg);
    assert(WriteLine !is null);
}
