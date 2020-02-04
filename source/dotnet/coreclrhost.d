module dotnet.coreclrhost;

// applies to function pointers
__gshared:

// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

//
// APIs for hosting CoreCLR
//


// For each hosting API, we define a function prototype and a function pointer
// The prototype is useful for implicit linking against the dynamic coreclr
// library and the pointer for explicit dynamic loading (dlopen, LoadLibrary)
//#define CORECLR_HOSTING_API(function, ...) \
//    extern "C" int CORECLR_CALLING_CONVENTION function(__VA_ARGS__); \
//    typedef int (CORECLR_CALLING_CONVENTION *function##_ptr)(__VA_ARGS__)
    
//
// Initialize the CoreCLR. Creates and starts CoreCLR host and creates an app domain
//
// Parameters:
//  exePath                 - Absolute path of the executable that invoked the ExecuteAssembly (the native host application)
//  appDomainFriendlyName   - Friendly name of the app domain that will be created to execute the assembly
//  propertyCount           - Number of properties (elements of the following two arguments)
//  propertyKeys            - Keys of properties of the app domain
//  propertyValues          - Values of properties of the app domain
//  hostHandle              - Output parameter, handle of the created host
//  domainId                - Output parameter, id of the created app domain 
//
// Returns:
//  HRESULT indicating status of the operation. S_OK if the assembly was successfully executed
//
extern(C) int coreclr_initialize(
            const (char)* exePath,
            const (char)* appDomainFriendlyName,
            int propertyCount,
            const (char*)* propertyKeys,
            const (char*)* propertyValues,
            void** hostHandle,
            uint* domainId);

extern(C) int function(
            const (char)* exePath,
            const (char)* appDomainFriendlyName,
            int propertyCount,
            const (char*)* propertyKeys,
            const (char*)* propertyValues,
            void** hostHandle,
            uint* domainId) coreclr_initialize_ptr;

//
// Shutdown CoreCLR. It unloads the app domain and stops the CoreCLR host.
//
// Parameters:
//  hostHandle              - Handle of the host
//  domainId                - Id of the domain
//
// Returns:
//  HRESULT indicating status of the operation. S_OK if the assembly was successfully executed
//
extern(C) int coreclr_shutdown(
            void* hostHandle,
            uint domainId);

extern(C) int function(
            void* hostHandle,
            uint domainId) coreclr_shutdown_ptr;

//
// Shutdown CoreCLR. It unloads the app domain and stops the CoreCLR host.
//
// Parameters:
//  hostHandle              - Handle of the host
//  domainId                - Id of the domain
//  latchedExitCode         - Latched exit code after domain unloaded
//
// Returns:
//  HRESULT indicating status of the operation. S_OK if the assembly was successfully executed
//
extern(C) int coreclr_shutdown_2(
            void* hostHandle,
            uint domainId,
            int* latchedExitCode);

extern(C) int function(
            void* hostHandle,
            uint domainId,
            int* latchedExitCode) coreclr_shutdown_2_ptr;

//
// Create a native callable function pointer for a managed method.
//
// Parameters:
//  hostHandle              - Handle of the host
//  domainId                - Id of the domain 
//  entryPointAssemblyName  - Name of the assembly which holds the custom entry point
//  entryPointTypeName      - Name of the type which holds the custom entry point
//  entryPointMethodName    - Name of the method which is the custom entry point
//  delegate                - Output parameter, the function stores a native callable function pointer to the delegate at the specified address
//
// Returns:
//  HRESULT indicating status of the operation. S_OK if the assembly was successfully executed
//
extern(C) int coreclr_create_delegate(
            void* hostHandle,
            uint domainId,
            const (char)* entryPointAssemblyName,
            const (char)* entryPointTypeName,
            const (char)* entryPointMethodName,
            void** delegate_);

extern(C) int function(
            void* hostHandle,
            uint domainId,
            const (char)* entryPointAssemblyName,
            const (char)* entryPointTypeName,
            const (char)* entryPointMethodName,
            void** delegate_) coreclr_create_delegate_ptr;

//
// Execute a managed assembly with given arguments
//
// Parameters:
//  hostHandle              - Handle of the host
//  domainId                - Id of the domain 
//  argc                    - Number of arguments passed to the executed assembly
//  argv                    - Array of arguments passed to the executed assembly
//  managedAssemblyPath     - Path of the managed assembly to execute (or NULL if using a custom entrypoint).
//  exitCode                - Exit code returned by the executed assembly
//
// Returns:
//  HRESULT indicating status of the operation. S_OK if the assembly was successfully executed
//
extern(C) int coreclr_execute_assembly(
            void* hostHandle,
            uint domainId,
            int argc,
            const (char*)* argv,
            const (char)* managedAssemblyPath,
            uint* exitCode);

extern(C) int function(
            void* hostHandle,
            uint domainId,
            int argc,
            const (char*)* argv,
            const (char)* managedAssemblyPath,
            uint* exitCode) coreclr_execute_assembly_ptr;