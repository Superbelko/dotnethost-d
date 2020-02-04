module dotnet.host;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.traits;

import core.stdc.stdlib;

import dotnet.coreclrhost;

public import dotnet.helpers;



struct NetCoreHost
{
    static NetCoreHost create()
    {
        auto version_ = find_dotnet_host();
        
        return NetCoreHost(version_);
    }

    static DotnetVersionInfo[] listVersions()
    {
        import std.algorithm;
        import std.range;

        static bool descending(DotnetVersionInfo a, DotnetVersionInfo b) {
            if (a.major == b.major)
                return a.minor > b.minor;
            else
                return a.major > b.major;
        }

        return list_dotnet_runtimes
            .map!parse_dotnet_version
            .array()
            .sort!descending
            .array()
            ;
    }


    this(DotnetVersionInfo useVersion)
    {
        _version = useVersion;
        _libHandle = loadLibrary(useVersion.path ~ dirSeparator ~ "coreclr.dll");
        loadPointers(_libHandle, &loadSymbol);
        //initializeCLR();
    }


    void initializeCLR(string[] trustedAssemblies)
    {
        
        auto tpa_list = AddFilesFromDirectoryToTPAList(getcwd(), trustedAssemblies, _version.path, rgTPAExtensions);

        // Allowed property names:
        // APPBASE
        // - The base path of the application from which the exe and other assemblies will be loaded
        //
        // TRUSTED_PLATFORM_ASSEMBLIES
        // - The list of complete paths to each of the fully trusted assemblies
        //
        // APP_PATHS
        // - The list of paths which will be probed by the assembly loader
        //
        // APP_NI_PATHS
        // - The list of additional paths that the assembly loader will probe for ngen images
        //
        // NATIVE_DLL_SEARCH_DIRECTORIES
        // - The list of paths that will be probed for native DLLs called by PInvoke
        //

        string[] property_keys = [
            "TRUSTED_PLATFORM_ASSEMBLIES",
            "APP_PATHS",
            "APP_NI_PATHS",
            "NATIVE_DLL_SEARCH_DIRECTORIES",
            //"APP_LOCAL_WINMETADATA",
        ];

        string[] property_values = [
            // TRUSTED_PLATFORM_ASSEMBLIES
            tpa_list,
            // APP_PATHS
            getcwd(),
            // APP_NI_PATHS
            getcwd(),
            // NATIVE_DLL_SEACH_DIRECTORIES
            getcwd(),
        ];

        import core.runtime;

        int ret = coreclr_initialize_ptr(
            Runtime.cArgs.argv[0],                  // exePath
            "host",                                 // appDomainFriendlyName
            cast(int) property_keys.length,
            property_keys.map!(toStringz).array.ptr,  // propertyKeys
            property_values.map!(toStringz).array.ptr,// propertyValues
            &_hostHandle,                        // hostHandle
            &_domainId                              // domainId
        );

        if (ret < 0)
            throw new Exception("Init failed");
    }


    void* getDelegate(string assembly, string type, string method)
    {
        void* res;
        coreclr_create_delegate_ptr(
            _hostHandle,
            _domainId,
            assembly.toStringz,
            type.toStringz,
            method.toStringz,
            cast(void**) &res
        );
        return res;
    }


    typeof(T) getDelegate(alias T)() if (isSomeFunction!T)
    {
        static assert(functionLinkage!T == "C", "Not supported calling convention for function " ~ T.stringof);
        
        return cast(typeof(T)) getDelegate(
            getAssembly!T, 
            getNamespace!T,
            getClassname!T
        );
    }



    DotnetVersionInfo _version;
    void* _libHandle;
    void* _hostHandle;
    uint _domainId;

    // injects function pointers from coreclrhost module
    static foreach(fptr; __traits(allMembers, dotnet.coreclrhost))
    {
        static if (isFunctionPointer!(__traits(getMember, dotnet.coreclrhost, fptr)))
        {
            //pragma(msg, typeof(__traits(getMember, dotnet.coreclrhost, fptr)).stringof);
            mixin(typeof(__traits(getMember, dotnet.coreclrhost, fptr)).stringof ," ", fptr, ";");
        }
    }

    // load pointers (locals)
    private void loadPointers(void* libHandle, void* function(void*, string) loaderFunction)
    {
        this.coreclr_initialize_ptr = cast(typeof(coreclr_initialize_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_initialize));
        this.coreclr_shutdown_ptr = cast(typeof(coreclr_shutdown_ptr))     loaderFunction(libHandle, __traits(identifier, coreclr_shutdown));
        this.coreclr_shutdown_2_ptr = cast(typeof(coreclr_shutdown_2_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_shutdown_2));
        this.coreclr_create_delegate_ptr = cast(typeof(coreclr_create_delegate_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_create_delegate));
        this.coreclr_execute_assembly_ptr = cast(typeof(coreclr_execute_assembly_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_execute_assembly));
    }
}


struct DotnetVersionInfo
{
    int major;
    int minor;
    int revision;
    string versionString;
    string path;
    bool isSDK;

    bool opEquals(const DotnetVersionInfo other) const
    {
        return (major == other.major 
            && minor == other.minor
            && revision == other.revision
            && versionString == other.versionString
            && path == other.path
            // SDK flag may mismatch after detection, so do not compare
            //&& isSDK == other.isSDK
        );
    }
}


private auto list_dotnet_sdk()
{
    import std.algorithm;
    import std.exception;
    import std.process;
    import std.range;
    import std.stdio;
    import std.string;

    auto res = execute(["dotnet", "--list-sdks"]);
    enforce(res.status == 0, "Something went wrong. Please make sure that 'dotnet' command is present in PATH environment variable");

    string[] versions = res.output
        .splitLines
        .retro
        .array()
        ;

    return versions;
}


private auto list_dotnet_runtimes()
{
    import std.algorithm;
    import std.exception;
    import std.process;
    import std.range;
    import std.stdio;
    import std.string;

    auto res = execute(["dotnet", "--list-runtimes"]);
    enforce(res.status == 0, "Something went wrong. Please make sure that 'dotnet' command is present in PATH environment variable");

    // since .NET Core 3 there is also Microsoft.WindowsDesktop.App, which may be desirable in some cases
    // but for now care only about regular app runtime, may add user supplied filter string later
    string[] versions = res.output
        .splitLines
        .retro
        .filter!(s => s.startsWith("Microsoft.NETCore.App"))
        .array()
        ;

    return versions;
}


private bool is_dotnet_present()
{
    import std.process;
    auto exec = execute(["dotnet", "--info"]);
    // TODO: check version and authenticity?
    return exec.status == 0;
}


/// Pick last version available as reported by dotnet executable
private DotnetVersionInfo find_dotnet_host()
{
    auto versions = list_dotnet_runtimes();

    if (versions.empty)
        throw new Exception("Unable to find .NET Core");

    auto last = versions[0];

    auto version_ = last.parse_dotnet_version();

    return version_;
}


DotnetVersionInfo parse_dotnet_version(string version_)
{
    import std.algorithm;
    import std.conv : to;
    import std.exception;
    import std.process;
    import std.range;
    import std.stdio;
    import std.string;

    //auto first = version_.split;
    auto firstVerSplitAt = version_.indexOf(' '); // split at first whitespace
    auto firstPathSplitAt = version_.indexOf(' ', 1+firstVerSplitAt); // split at second whitespace (if any)

    string ver; 
    string path;

    bool isSDK = !version_.startsWith("Microsoft.");
    if (isSDK)
    {
        ver = version_[0..firstVerSplitAt].idup;
        path = version_[1+firstVerSplitAt..$].idup;
    }
    else
    {
        ver = version_[1+firstVerSplitAt..firstPathSplitAt].idup;
        path = version_[1+firstPathSplitAt..$].idup;
    }

    // strip square brackets
    if (path[0] == '[')
        path = path[1..$-1];
    
    path ~= dirSeparator ~ ver;

    version(LongBuilds)
    {
      import std.regex;
      static immutable versionPattern = regex(`([\d]+)\.([\d]+)\.([\d]+)(\-[-.\w\S\d]+)*.*`);
      auto m = match((isSDK ? version_[0..firstVerSplitAt] : version_[1+firstVerSplitAt..$]), versionPattern);
      auto major = to!int( m.captures[1]);
      auto minor = to!int( m.captures[2]);
      auto rev = to!int( m.captures[3]);
    }
    else
    {
      int major = 0;
      int minor = 0;
      int rev = 0;

      auto m = (isSDK ? version_[0..firstVerSplitAt] : version_[1+firstVerSplitAt..$]);
      auto pos = m.indexOf('.');
      auto next = pos;
      if (pos > 0)
      {
          major = to!int(m[0..next]);
          next = m.indexOf('.', pos+1);
          if (next > 0)
          {
              minor = to!int(m[pos+1..next]);
              pos = next;
              // next pick either '-', ' ' or last index in string
              next = m.indexOf('-', pos+1);
              if (next == -1)
              {
                  next = m.indexOf(' ', pos+1);
                  if (next == -1)
                  {
                      next = m.length;
                  }
              }
              rev = to!int(m[pos+1..next]);
          }
      }
    }

    return DotnetVersionInfo(major, minor, rev, ver, path, isSDK);
}


unittest
{
    // sdks
    //2.2.6 [C:\Program Files\dotnet\sdk]
    //3.0.100-preview8-013656 [C:\Program Files\dotnet\sdk]

    import std.stdio;

    auto winsdk = parse_dotnet_version(`2.2.301 [C:\Program Files\dotnet\sdk]`);    
    assert(winsdk == DotnetVersionInfo(2,2,301, `2.2.301`, `C:\Program Files\dotnet\sdk\2.2.301`, true));


    auto winsdkPreview = parse_dotnet_version(`3.0.100-preview8-013656 [C:\Program Files\dotnet\sdk]`);
    assert(winsdkPreview == DotnetVersionInfo(3,0,100, `3.0.100-preview8-013656`, `C:\Program Files\dotnet\sdk\3.0.100-preview8-013656`));

    // runtimes only
    //Microsoft.AspNetCore.All 2.1.12 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.All]
    //Microsoft.AspNetCore.All 2.2.6 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.All]
    //Microsoft.AspNetCore.App 2.2.6 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
    //Microsoft.AspNetCore.App 3.0.0-preview8.19405.7 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
    //Microsoft.NETCore.App 1.0.5 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
    //Microsoft.NETCore.App 2.2.6 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
    //Microsoft.NETCore.App 3.0.0-preview8-28405-07 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
    //Microsoft.WindowsDesktop.App 3.0.0-preview8-28405-07 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]

    auto winrtPreview = parse_dotnet_version(`Microsoft.NETCore.App 3.0.0-preview8-28405-07 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]`);
    assert(winrtPreview == DotnetVersionInfo(3,0,0, `3.0.0-preview8-28405-07`, `C:\Program Files\dotnet\shared\Microsoft.NETCore.App\3.0.0-preview8-28405-07`));
}


// The rest is internal stuff that need not be visible
private:

version(Windows)
{
    import std.string;
    import std.utf;
    import core.sys.windows.windows;
    
    void* loadLibrary(string lib) { return LoadLibrary(lib.toUTF16z); }
    void* loadSymbol(void* lib, string symname) { return GetProcAddress(lib, symname.toStringz); }
}
else
{
    import std.string;
    import core.sys.posix.dlfcn;

    void* loadLibrary(string lib) { return dlopen(lib.toStringz, RTLD_NOW); }
    void* loadSymbol(void* lib, string symname) { return dlsym(lib, symname.toStringz); }
}


// load global pointers
void loadPointers(void* libHandle, void* function(void*, string) loaderFunction)
{
    coreclr_initialize_ptr = cast(typeof(coreclr_initialize_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_initialize));
	coreclr_shutdown_ptr = cast(typeof(coreclr_shutdown_ptr))     loaderFunction(libHandle, __traits(identifier, coreclr_shutdown));
	coreclr_shutdown_2_ptr = cast(typeof(coreclr_shutdown_2_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_shutdown_2));
	coreclr_create_delegate_ptr = cast(typeof(coreclr_create_delegate_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_create_delegate));
	coreclr_execute_assembly_ptr = cast(typeof(coreclr_execute_assembly_ptr)) loaderFunction(libHandle, __traits(identifier, coreclr_execute_assembly));
}


immutable string[] rgTPAExtensions = [
    ".ni.dll",		// Probe for .ni.dll first so that it's preferred if ni and il coexist in the same dir
    ".dll",
    ".ni.exe",
    ".exe",
    ".ni.winmd",
    ".winmd"
];


string AddFilesFromDirectoryToTPAList(string appPath, string[] userLibs, string targetPath, const string[] rgTPAExtensions)
{
    auto res = appender!string();

    auto path = targetPath;
    if (!path.isDir)
        path = dirName(path);

    dirEntries(path, SpanMode.depth)
        .filter!( a => a.isFile )
        .filter!( a => rgTPAExtensions.canFind(extension(a.name)) )
        .each!( (a) { res.put(a.name); res.put(pathSeparator); })
        ;

    userLibs.each!( (a) { res.put(a); res.put(pathSeparator); });

    res.put('\0');

    return res.data;
}

