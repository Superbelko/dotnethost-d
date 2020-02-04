module dotnet.helpers;

import std.traits;


/// Assembly name for the type
struct AssemblyAttr { string name; }
/// ditto
@property AssemblyAttr assembly(string name) { return AssemblyAttr(name); }


/// Namespace for the type
struct NamespaceAttr { string name; }
/// ditto
@property NamespaceAttr namespace(string ns) { return NamespaceAttr(ns); }

/// Marks symbol with new name to use for wrapper generator, handy for keywords names
struct SymNameAttr { string name; }
/// ditto
@property SymNameAttr symname(string newName) { return SymNameAttr(newName); }



/// assembly name for user defined type
enum getAssembly(alias T) = getUDAs!(T, AssemblyAttr)[0].name;


/// same, but with custom default
template getAssembly(alias T, string default_)
{
    static if (getUDAs!(T, AssemblyAttr).length)
        enum getAssembly = getUDAs!(T, AssemblyAttr)[0].name;
    else 
        enum getAssembly = default_;
} 


/// Retrieves C# namespace for user defined type
template getNamespace(alias T)
{
    static if (hasUDA!(T, NamespaceAttr))
        enum getNamespace = getUDAs!(T, NamespaceAttr)[0].name;
    else
        enum getNamespace = "";
}


/// Resulting type name (if rename is present)
template getClassname(alias T)
{
    static if (getUDAs!(T, SymNameAttr).length)
        enum getClassname = getUDAs!(T, SymNameAttr)[0].name;
    else
        enum getClassname = __traits(identifier, T);
}