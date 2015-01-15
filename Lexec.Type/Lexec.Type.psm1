#Requires -Version 5.0.9883.0
#Requires -Modules Poke
Set-StrictMode -Version Latest

Add-Type -Language Csharp -TypeDefinition @'
    using System;
    using System.ComponentModel;
    using System.Management.Automation;
    using System.Collections.ObjectModel;
     
    [AttributeUsage(AttributeTargets.Class)]
    public class MetaClassAttribute : Attribute {
    
        public String namespaceName  { get; set; }
        public Type   baseType   { get; set; }
        public Type[] interfaces { get; set; }
        
        public MetaClassAttribute() {
            this.namespaceName = "";
            this.baseType = typeof(Object);
            this.interfaces = new Type[1];
        }
        
        public MetaClassAttribute(string NamespaceName, Type BaseType) {
            this.namespaceName = NamespaceName;
            this.baseType = BaseType;
        }
        
        public MetaClassAttribute(Type BaseType, params Type[] Interfaces) {
            this.baseType = BaseType;
            this.interfaces = Interfaces;
        }
        
        public MetaClassAttribute(string NamespaceName, Type BaseType, params Type[] Interfaces ) {
            this.namespaceName = NamespaceName;
            this.baseType = BaseType;
            this.interfaces = Interfaces;
        }
        
        public override string ToString() {
            return string.Format("[MetaClass({0}, {1}, {2})]", namespaceName, baseType, string.Join<Type>(", ", interfaces));
        }
       
    }
'@ 

class ClassType {
    
    # Input
    [string] $NamespaceName = [string]::Empty
    [scriptBlock] $ScriptBlock = $null
    [string[]] $ScriptCode = [string]::Empty
    [string[]] $FilePath = [string]::Empty
    [bool] $Passthru = $false
    [System.Management.Automation.Language.ScriptBlockAst] $ScriptBlockAst
    
    [string] $AssemblyName = 'Powershell'
    [version] $AssemblyVersion = [version]'1.0.0'
    [string] $ModuleName = 'PowershellVersion'
    [System.Reflection.Emit.AssemblyBuilderAccess]$AssemblyBuilderAccess = [System.Reflection.Emit.AssemblyBuilderAccess]::Run
    [string] $AssemblyDirectory = $global:ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
    [string] $AssemblyFileName = 'powershell.dll'

    static [PSObject] $Parser
    static [System.AppDomain] $CurrentDomain = [System.AppDomain]::CurrentDomain
    static [System.Reflection.Emit.AssemblyBuilder] $AssemblyBuilder
    static [System.Reflection.Emit.ModuleBuilder] $ModuleBuilder
    static [Type] $xlr8r = [psobject].assembly.gettype("System.Management.Automation.TypeAccelerators")
    
    # Output
    [type[]] $OutputTypes = [Type]::EmptyTypes

    hidden Initialize() {
        
        # Transform ScriptBlock to string
        if (-not [string]::IsNullOrEmpty($this.NamespaceName)) {
            $this.ScriptCode += "namespace {0} {{`n" -f $this.NamespaceName
            $this.ScriptCode += $this.ScriptBlock.ToString().Split("`n").Foreach({"`t{0}`n" -f $_}).ToString()
            $this.ScriptCode += "}`n"
        }
        
        # Get File Content if input is script
        if (-not [string]::IsNullOrEmpty($this.FilePath)) {
            foreach($Path in $this.FilePath) {
                if (Test-Path $Path) {
                    $this.ScriptCode += [System.IO.File]::ReadAllText($path)
                }
                else {
                    Write-Warning ( "Path {0} does not exist" -f $Path )
                }
            }
        }
        
        
        if ([ClassType]::AssemblyBuilder -eq $null) {
            
            # Assembly Builder and ModuleBuilder
            $Assembly = [System.Reflection.AssemblyName]::new($this.AssemblyName)
            $Assembly.Version = $this.AssemblyVersion
        
            If ($this.AssemblyBuilderAccess -in "Save","RunAndSave" ) {
                [ClassType]::AssemblyBuilder = [ClassType]::CurrentDomain.DefineDynamicAssembly(
                    $Assembly,
                    $this.AssemblyBuilderAccess -as [System.Reflection.Emit.AssemblyBuilderAccess] ,
                    $this.AssemblyDirectory
                )
                [ClassType]::ModuleBuilder = [ClassType]::assemblyBuilder.DefineDynamicModule(
                    $this.ModuleName,
                    $this.AssemblyFileName,
                    $false
                )
            }
            else {
                [ClassType]::AssemblyBuilder = [ClassType]::CurrentDomain.DefineDynamicAssembly($this.AssemblyName,'Run')
                [ClassType]::ModuleBuilder = [ClassType]::AssemblyBuilder.DefineDynamicModule($this.ModuleName)
            }
        }
       
    }

    
    [System.Type[]] Parse() {
        $results = $null

        # Initialize
        if ([ClassType]::AssemblyBuilder -eq $null) {
            $this.Initialize()
        }

        # Parser
        [ClassType]::Parser = (New-TypeProxy 'System.Management.Automation.Language.Parser').__CreateInstance()
        
        # Manage ScriptBlock, ScriptCode, ScriptPath
        if ($this.ScriptBlock -ne $null) {
            # Get Ast from ScriptBlock
            $this.scriptBlockAst = $this.ScriptBlock.Ast
        }
        else {
            # Get Ast from Compiler
            [System.Collections.Generic.List[System.Management.Automation.Language.Token]] $tokenList = @()
            [System.Management.Automation.Language.ParseError[]] $parseErrors = @()
            $this.scriptBlockAst = [ClassType]::Parser.Parse(
                $null, 
                $this.ScriptCode -As [string], 
                $TokenList, 
                $ParseErrors
            )
        }
        
        # Set assembly to the AST, some function like defineTypeHelper change AST after visit him or emit field or method. 
        (New-ObjectProxy -InputObject $this.ScriptblockAst).ImplementingAssembly = [ClassType]::AssemblyBuilder
 
        # Get Namespace from AST if it is not global
        if ([string]::IsNullOrEmpty($this.NamespaceName)) {
            $this.NamespaceName =   $this.scriptBlockAst.FindAll({
                                        Param($Ast)
                                        $Ast.Where({
                                            $_ -is [System.Management.Automation.Language.StringConstantExpressionAST] -and
                                            $_.StringConstantType -eq 'BareWord' -and 
                                            $_.StaticType.Name -eq 'string'
                                        })
                                    }, $false ) | Select-Object -Index 1
        }
        
        # Get Definition List from AST 
        $typeDefinitionList = $this.scriptBlockAst.FindAll({param($ast) Where-Object -Input $ast -FilterScript { $_ -is [System.Management.Automation.Language.TypeDefinitionAst] } }, $true)
        
        # Browse Definition List
        foreach ($typeDefinitionAst in $typeDefinitionList) {
            Write-Verbose ( "Parse class {0}" -f $typeDefinitionAst.Name )
            
            try {
                $Type = $this.ParseTypeDefinitionAst($typeDefinitionAst)
                if ($Type) {
                    $this.OutputTypes += $Type
                }
            }
            catch {
                Write-Host -Foreground Red ( "[Error] {0} : `n{1}"-f $typeDefinitionAst.Name , $_.Exception )
            }
        }
        
        
        if ($this.AssemblyBuilderAccess -band "Save") {
            [void] [ClassType]::AssemblyBuilder.Save($this.AssemblyFileName)
        }
        
        if ($This.PassThru) {
            $results = $this.OutputTypes
        }

        return $results
    }


    [System.Type] ParseTypeDefinitionAst([System.Management.Automation.Language.TypeDefinitionAst]$TypeDefinitionAst) {
        
        $Type = $null
        
        $className = $typeDefinitionAst.Name
        $staticClassName = "{0}<staticHelpers>" -f $typeDefinitionAst.Name
        
        $NamespaceName = [string]::Empty
        
        [Type] $parentType = $null
        [type[]] $interfaces = [Type]::EmptyTypes
        
        Write-Debug "Get Attributes"
        
        $Attributes = $TypeDefinitionAst.Attributes
        if ($Attributes) {
            
            foreach($Attribute in $Attributes) {
            
                if ($Attribute.NamedArguments.Count -gt 0) {
                    $Arguments = $Attribute.NamedArguments
                
                    [Regex] $pattern = "[\(\)\[\]]" 
                    
                    Write-Debug "Attribute NamespaceName and ClassName"
                    $NamespaceNameArgs = $Arguments.Where({$_.ArgumentName -eq 'NamespaceName'})
                    if ($NamespaceNameArgs -and $NamespaceNameArgs.Argument) {
                        $NamespaceName = $NamespaceNameArgs.Argument.Tostring().Replace("'","")
                    }
                    
                    Write-Debug "Parent Type"
                    $parentTypeArgs = $Arguments.Where({$_.ArgumentName -eq 'BaseType'})
                    if ($parentTypeArgs -and $parentTypeArgs.Argument) {
                        $ParentType = $pattern.Replace($parentTypeArgs.Argument.Tostring(),'') -As [Type]
                    }
                   
                    Write-Debug "Interfaces"
                    $interfacesArgs = $Arguments.Where({$_.ArgumentName -eq 'Interfaces'})
                    if ($interfacesArgs -and $interfacesArgs.Argument) {
                        $interface = $pattern.Replace($interfacesArgs.Argument.Tostring(),'').ToString().Split(',') -As [string[]]
                        if ($interface.Count -ge 1) {
                           $interfaces = $interface.Foreach({$_ -As [Type]}) -As [type[]]
                        }
                    }
                    
                }
                elseif ($Attribute.PositionalArguments.Count -gt 0) {
                   
                    $Arguments = $Attribute.PositionalArguments
                    if ( $Arguments[0].StaticType.Name -eq 'string' )  {
                        $NamespaceName = $Arguments[0].Value.ToString().Replace("'","")
                        if ($Attribute.PositionalArguments.Count -gt 1) {
                            $ParentType = $Arguments[1].TypeName.Name -As [Type]
                        }
                        if ($Attribute.PositionalArguments.Count -gt 2) {
                            $interfaces = ( $Arguments[2].TypeName.Name -As [Type] ) -As [Type[]]
                        }
                    }
                    elseif ( $Arguments[0].StaticType -is [Type] ) {
                        $parentType = $Arguments[0].TypeName.Name
                        if ($Attribute.PositionalArguments.Count -gt 1) {
                            $interfaces = ( $Arguments[1].TypeName.Name -As [Type] ) -As [Type[]]
                        }
                    }
                   
                }
                
               
            }
        }
        
        Write-Host "$ClassName"
        
        $CurrentNamespaceName = [string]::Empty 
       
        
        # if Namespace is defined globally is prior to define namespace
        # else it use namespace from an attribute of scriptblock AST
        if (-not [string]::IsNullOrEmpty($this.NamespaceName)) {
             $CurrentNamespaceName = $this.NamespaceName
        }
        elseif (-not [string]::IsNullOrEmpty($NamespaceName)) {
            $CurrentNamespaceName = $NamespaceName
        }
        
        if (-not [string]::IsNullOrEmpty($CurrentNamespaceName)) {
            $className = "{0}.{1}" -f $CurrentNamespaceName,$className
            $staticClassName = "{0}.{1}" -f $CurrentNamespaceName,$staticClassName
        }
        
        Write-Host ( "Class : {0} ParentType : {1} Interfaces : {2}" -f $className, $parentType, $interfaces )
        
        # We need a dummy ModuleBuilder (in a dummy AssemblyBuilder) to initialize the defineTypeHelper
        # DefineTypeHelper defines the type in the constructor, but we need to call an alternate DefineType 
        $DummyAssemblyBuilder = [ClassType]::CurrentDomain.DefineDynamicAssembly([System.Reflection.AssemblyName]::new('DummyAssembly'),[System.Reflection.Emit.AssemblyBuilderAccess]::Run)
        $DummyModuleBuilder = $DummyAssemblyBuilder.DefineDynamicModule('DummyModule')
        $defineTypeHelper = (New-TypeProxy 'System.Management.Automation.Language.TypeDefiner+DefineTypeHelper').__CreateInstance(
            [System.Management.Automation.Language.Parser]$([ClassType]::Parser.__GetBaseObject()),
            [System.Reflection.Emit.ModuleBuilder]$DummyModuleBuilder,
            [System.Management.Automation.Language.TypeDefinitionAst]$typeDefinitionAst,
            [string]$ClassName
        )
        $DummyModuleBuilder = $null
        $DummyAssemblyBuilder = $null
        
        # Hacking DefineTypeHelper:
        # Replace the dummy module builder, and call DefineType with support for BaseType and Interfaces
        $defineTypeHelper._ModuleBuilder = [ClassType]::ModuleBuilder
       
        Write-Debug "Define Type and static Type"
        try {
        
            Write-Debug "Type"
            if ($Interfaces -ne [Type]::EmptyTypes) {
                Write-Debug "Declare Interface"
                if ([string]::IsNullOrEmpty($parentType) ) {
                    $parenType = [object]
                }
                $defineTypeHelper._typeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                    $className, 
                    [System.Reflection.TypeAttributes]'Public', 
                    $ParentType, 
                    $Interfaces
               )
            }
            elseif( -not [string]::IsNullOrEmpty($parentType) ) {
                Write-Debug "Declare Parent"
                $defineTypeHelper._typeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                    $className, 
                    [System.Reflection.TypeAttributes]'Public',
                    $ParentType
                )
            }
            else {
                 Write-Debug "Declare Simple Class"
                 $defineTypeHelper._typeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                    $className, 
                    [System.Reflection.TypeAttributes]'Public'
                )
            }
            
            Write-Debug "Static Type"
            $defineTypeHelper._staticHelpersTypeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                $staticClassName, 
                [System.Reflection.TypeAttributes]"NotPublic"
            )
            
            Write-Debug "Create Members"
            $defineTypeHelper.DefineMembers()
          
            Write-Debug "Create TypeInfo"
            $Type = $defineTypeHelper._typeBuilder.CreateTypeInfo()
            $TypeStatic = $defineTypeHelper._staticHelpersTypeBuilder.CreateTypeInfo()

            Write-Debug " Update ScriptBlockMemberMethodWrapper Field , only work with AssemblyBuilderAccess set to Run or RunAndSave"
            if ($defineTypeHelper._fieldsToInitForMemberFunctions -ne $null) {
                foreach ($tuple in $defineTypeHelper._fieldsToInitForMemberFunctions) {
                    $Field = $defineTypeHelper._staticHelpersTypeBuilder.GetField([string]$tuple.Item1,[System.Reflection.BindingFlags]"Static,NonPublic")
                    $Field.SetValue([System.Management.Automation.Internal.AutomationNull]::Value, [System.Management.Automation.ScriptBlockMemberMethodWrapper]$tuple.Item2)
                }
            }
                
            Write-Debug "Create Type"
            [void] $defineTypeHelper._typeBuilder.CreateType()
            [void] $defineTypeHelper._staticHelpersTypeBuilder.CreateType()
            $defineTypeHelper = $null
            
            Write-Debug "Add Accelerator"
            [void] [ClassType]::xlr8r::Remove($ClassName)
            [void] [ClassType]::xlr8r::Add($ClassName, $Type)
        }
        catch {
            Write-Host -Foreground Red ( "[ERROR] {0} : `n{1}"-f $className , $_.Exception )
        }
        
        # Return Type
        return $Type
    }

}
function Add-ClassType {
    [OutputType([Type[]])]
    [CmdletBinding(DefaultParameterSetName='ScriptBlock')]
    Param(
    
        [Parameter(Mandatory=$false,ParameterSetName="ScriptBlock",Position=0)]
        [Parameter()]
        [string]
        $NamespaceName,
        
        [Parameter(Mandatory=$true,ParameterSetName="ScriptBlock",Position=1)]
        [ValidateNotNullOrEmpty()]
        [Alias("Script","Block")]
        [scriptblock] 
        $ScriptBlock,
        
        [Parameter(Mandatory=$true,ParameterSetName="Code")]
        [ValidateNotNullOrEmpty()]
        [Alias("Code")]
        [string[]] 
        $ScriptCode,
        
        [Parameter(Mandatory=$true,ParameterSetName="File")]
        [ValidateNotNullOrEmpty()]
        [Alias("File","Path")]
        [string[]]
        $FilePath,
        
        [Parameter()]
        [switch]
        $PassThru,

        [Parameter()]
        [ValidateSet('Run','RunAndSave','Save')]
        [Alias("BuilderAccess","Access")]
        [System.Reflection.Emit.AssemblyBuilderAccess]
        $AssemblyBuilderAccess,

        [Parameter()]
        [string]
        $AssemblyPath,
        
        [Parameter()]
        [string]
        $AssemblyName,

        [Parameter()]
        [string]
        $ModuleName,
        
        [Parameter()]
        [version]
        $AssemblyVersion

    )
    $Types = [Type]::EmptyTypes
    $CommonParameters = 'Verbose,Debug,WarningAction,ErrorAction,ErrorVariable,WarningVariable,OutVariable,OutBuffer,PipelineVariable' -split ','
    $Parameters = @{}
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Key -notin $CommonParameters) {
            Write-Verbose ("Parameter {0}={1}" -f $Parameter.key,$Parameter.Value)
            $Parameters.Add($Parameter.Key,$Parameter.Value)
        }
    }
    $ClassType = [ClassType]$Parameters
    $Types = $ClassType.Parse()
    return $Types
}

$ExecutionContext.SessionState.Module.OnRemove = {
    
}

Export-ModuleMember -Function Add-ClassType