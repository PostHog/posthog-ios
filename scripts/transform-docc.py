#!/usr/bin/env python3

"""
PostHog iOS SDK DocC Documentation Transformer

Transforms DocC-generated documentation directory into the format required by the PostHog documentation website.
This version parses the individual JSON files in the DocC data directory structure.
"""

import json
import sys
import os
import re
from typing import Dict, List, Any, Optional
from pathlib import Path

def categorize_method(method_name: str, class_name: str = "") -> str:
    """Categorize methods based on their names and functionality."""
    
    # Initialization methods
    if method_name in ["setup", "with"] or "init" in method_name.lower():
        return "Initialization"
    
    # Identification methods  
    if method_name in ["identify", "alias", "getDistinctId", "getAnonymousId"]:
        return "Identification"
    
    # Capture methods
    if method_name in ["capture", "screen", "autocapture", "flush", "register", "unregister"]:
        return "Capture"
    
    # Feature flag methods
    if any(flag_term in method_name.lower() for flag_term in ["feature", "flag", "reload"]):
        return "Feature flags"
    
    # Session replay methods
    if any(replay_term in method_name.lower() for replay_term in ["session", "recording", "replay"]):
        return "Session replay"
    
    # Privacy methods
    if method_name in ["optOut", "optIn", "reset", "isOptOut"]:
        return "Privacy"
    
    # Configuration methods
    if method_name in ["debug", "close"] or method_name.startswith("get"):
        return "Configuration"
    
    # Default fallback
    return "Configuration"


def extract_parameters_from_docc(method_data: Dict, declaration_fragments: List[Dict] = None, method_title: str = "") -> List[Dict]:
    """Extract parameters from DocC method data according to DocC format standards."""
    params = []
    
    # First try to get parameters from DocC primaryContentSections (preferred)
    docc_parameters = []
    primary_sections = method_data.get("primaryContentSections", [])
    for section in primary_sections:
        if section.get("kind") == "parameters":
            docc_parameters = section.get("parameters", [])
            print(f"    Found DocC parameters section: {docc_parameters}")
            break
    if docc_parameters:
        for param in docc_parameters:
            param_name = param.get("name", "")
            param_description = ""
            
            # Extract description from content array (DocC format)
            content = param.get("content", [])
            if content and isinstance(content, list):
                description_parts = []
                for item in content:
                    if isinstance(item, dict):
                        # Check for inlineContent structure
                        inline_content = item.get("inlineContent", [])
                        if inline_content:
                            for inline_item in inline_content:
                                if isinstance(inline_item, dict) and inline_item.get("type") == "text":
                                    description_parts.append(inline_item.get("text", ""))
                        # Fallback to direct text
                        elif item.get("text"):
                            description_parts.append(item.get("text", ""))
                param_description = " ".join(description_parts)
                print(f"    Extracted param description for '{param_name}': '{param_description}'")
            
            # Extract type from declaration fragments if available
            param_type = "Any"
            if declaration_fragments:
                param_type = extract_parameter_type_from_fragments(declaration_fragments, param_name)
            
            params.append({
                "name": param_name,
                "type": param_type,
                "description": param_description,
                "isOptional": "?" in param_type
            })
        return params
    
    # Fallback: extract from declaration fragments
    if declaration_fragments:
        return extract_parameters_from_declaration_fragments(declaration_fragments, method_title)
    
    return params

def extract_parameter_type_from_fragments(declaration_fragments: List[Dict], param_name: str) -> str:
    """Extract parameter type from declaration fragments for a specific parameter."""
    # Look for parameter name followed by type in fragments
    found_param = False
    for i, fragment in enumerate(declaration_fragments):
        text = fragment.get("text", "")
        kind = fragment.get("kind", "")
        
        if text == param_name and kind == "externalParam":
            found_param = True
        elif found_param and kind == "typeIdentifier":
            return text
    
    return "Any"

def extract_parameters_from_declaration_fragments(declaration_fragments: List[Dict], method_title: str = "") -> List[Dict]:
    """Extract parameters from DocC declaration fragments (fallback method)."""
    params = []
    
    # Look for parameter patterns in declaration fragments
    in_params = False
    param_index = 0
    current_param_name = None
    
    for i, fragment in enumerate(declaration_fragments):
        text = fragment.get("text", "")
        kind = fragment.get("kind", "")
        
        if text == "(":
            in_params = True
            continue
        elif text == ")":
            break
        elif not in_params:
            continue
        elif kind == "externalParam":
            current_param_name = text
        elif kind == "typeIdentifier" and current_param_name:
            params.append({
                "name": current_param_name,
                "type": text,
                "description": f"The {current_param_name} parameter",
                "isOptional": "?" in text
            })
            current_param_name = None
            param_index += 1
        elif kind == "typeIdentifier" and not current_param_name:
            # Unnamed parameter
            param_name = infer_parameter_name(method_title, param_index)
            params.append({
                "name": param_name,
                "type": text,
                "description": f"The {param_name} parameter",
                "isOptional": "?" in text
            })
            param_index += 1
    
    return params

def infer_parameter_name(method_title: str, param_index: int) -> str:
    """Infer parameter name from method title and index."""
    if not method_title:
        return f"param{param_index}"
    
    base_method_name = method_title.split("(")[0] if "(" in method_title else method_title
    
    # Common parameter name patterns
    if "alias" in base_method_name.lower():
        return "alias"
    elif "identify" in base_method_name.lower():
        return "distinctId"
    elif "capture" in base_method_name.lower():
        return "event" if param_index == 0 else "properties"
    elif "screen" in base_method_name.lower():
        return "name" if param_index == 0 else "properties"
    elif "group" in base_method_name.lower():
        return "type" if param_index == 0 else "key"
    else:
        return f"param{param_index}"

def parse_class_json(class_file_path: str) -> Dict:
    """Parse a DocC class JSON file to extract methods and details."""
    
    try:
        with open(class_file_path, 'r') as f:
            class_data = json.load(f)
    except Exception as e:
        print(f"❌ Error reading {class_file_path}: {e}")
        return {}
    
    class_info = {
        "functions": []
    }
    
    # Extract class description
    abstract = class_data.get("abstract", [])
    if abstract and isinstance(abstract, list):
        description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
        class_info["description"] = description
    
    # Look for relationships to find methods
    relationships = class_data.get("relationships", {})
    
    # Check for memberOf relationships (methods belonging to this class)
    members = relationships.get("memberOf", [])
    
    for member in members:
        member_title = member.get("title", "")
        member_kind = member.get("kind", "")
        
        if any(method_kind in member_kind for method_kind in ["method", "initializer", "func"]):
            # Extract method details
            method_name = member_title
            category = categorize_method(method_name)
            
            # Extract parameters from declaration if available
            params = []
            declaration = member.get("declaration", {})
            if declaration and "declarationFragments" in declaration:
                params = extract_parameters_from_declaration(declaration["declarationFragments"])
            
            method_info = {
                "category": category,
                "description": member.get("abstract", {}).get("text", f"{method_name} method"),
                "id": method_name,
                "showDocs": True,
                "title": method_name,
                "releaseTag": "public",
                "params": params,
                "returnType": {
                    "id": "Void",
                    "name": "Void"
                },
                "path": f"PostHog/{class_info.get('title', 'Unknown')}.swift"
            }
            
            # Only add details if there's actual discussion content
            discussion = member.get("discussion", {})
            if discussion and discussion.get("content"):
                details_text = discussion.get("content", [{}])[0].get("text", "")
                if details_text:
                    method_info["details"] = details_text
            
            class_info["functions"].append(method_info)
    
    return class_info

def process_docc_directory(docc_data_dir: str, version: str) -> Dict:
    """Process the entire DocC data directory structure."""
    
    result = {
        "id": "posthog-ios",
        "hogRef": "0.3",
        "info": {
            "version": version,
            "id": "posthog-ios", 
            "title": "PostHog iOS SDK",
            "description": "PostHog iOS SDK allows you to automatically capture usage and send events to PostHog from iOS applications.",
            "slugPrefix": "posthog-ios",
            "specUrl": "https://github.com/PostHog/posthog-ios"
        },
        "classes": [],
        "types": [],
        "categories": [
            "Initialization",
            "Identification", 
            "Capture",
            "Feature flags",
            "Session replay",
            "Privacy",
            "Configuration"
        ]
    }
    
    classes = {}
    types = {}
    
    # Find PostHog-related JSON files
    docc_path = Path(docc_data_dir)
    posthog_dir = docc_path / "posthog"
    
    if not posthog_dir.exists():
        print(f"❌ PostHog directory not found in {docc_data_dir}")
        return result
    
    print(f"📊 Processing DocC directory: {posthog_dir}")
    
    # Process all JSON files in the posthog directory
    for json_file in posthog_dir.glob("**/*.json"):
        file_name = json_file.stem
        
        # Skip non-PostHog files
        if not any(term in file_name.lower() for term in ["posthog"]):
            continue
            
        print(f"🔍 Processing file: {json_file.name}")
        
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
        except Exception as e:
            print(f"❌ Error reading {json_file}: {e}")
            continue
        
        # Extract basic info with better error handling
        try:
            metadata = data.get("metadata", {})
            if isinstance(metadata, dict):
                title = metadata.get("title", file_name)
            else:
                title = file_name
                
            kind_data = data.get("kind", {})
            if isinstance(kind_data, dict):
                kind = kind_data.get("identifier", "")
            else:
                kind = str(kind_data) if kind_data else ""
        except Exception as e:
            print(f"❌ Error extracting metadata from {json_file}: {e}")
            print(f"   Data keys: {list(data.keys()) if isinstance(data, dict) else 'Not a dict'}")
            continue
        
        print(f"  📝 Found: {title} ({kind})")
        
        # Handle classes - DocC uses 'symbol' as kind, check metadata for actual type
        metadata = data.get("metadata", {})
        symbol_kind = metadata.get("symbolKind", "")
        
        if (kind == "symbol" and symbol_kind == "class" and "PostHog" in title):
            if title not in classes:
                # Extract description
                abstract = data.get("abstract", [])
                description = ""
                if abstract and isinstance(abstract, list):
                    description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
                elif isinstance(abstract, str):
                    description = abstract
                
                classes[title] = {
                    "description": description or f"The {title} class",
                    "id": title,
                    "title": title,
                    "functions": []
                }
                
                # Look for topicSections which contain methods
                topic_sections = data.get("topicSections", [])
                for section in topic_sections:
                    section_title = section.get("title", "")
                    print(f"    Processing section: {section_title}")
                    
                    # Process all sections: methods, properties, initializers, etc.
                    if section_title and section.get("identifiers"):
                        identifiers = section.get("identifiers", [])
                        print(f"      Found {len(identifiers)} methods")
                        
                        for method_id in identifiers:
                            # Look up method details in references
                            references = data.get("references", {})
                            method_ref = references.get(method_id, {})
                            
                            if method_ref:
                                method_title = method_ref.get("title", "")
                                method_kind = method_ref.get("kind", "")
                                
                                print(f"        Method: {method_title}")
                                
                                # Clean up method name (remove Swift syntax like (_:))
                                clean_method_name = method_title.split("(")[0] if "(" in method_title else method_title
                                
                                # Extract method details
                                category = categorize_method(clean_method_name, title)
                                
                                # Extract parameters using DocC format standards
                                params = []
                                fragments = method_ref.get("fragments", [])
                                print(f"          Fragments: {fragments[:5]}...")  # Show first 5 fragments
                                
                                # Load individual method file for detailed parameter documentation
                                method_data = {}
                                if method_id.startswith("doc://"):
                                    # Convert doc URL to file path
                                    method_path = method_id.replace("doc://PostHog/documentation/", "").replace("/", "/").lower()
                                    method_file_path = os.path.join(docc_data_dir, method_path + ".json")
                                    
                                    if os.path.exists(method_file_path):
                                        try:
                                            with open(method_file_path, 'r', encoding='utf-8') as f:
                                                method_data = json.load(f)
                                                print(f"          Loaded method file: {method_file_path}")
                                        except Exception as e:
                                            print(f"          Error loading method file {method_file_path}: {e}")
                                
                                params = extract_parameters_from_docc(method_data, fragments, method_title)
                                print(f"          Extracted params: {params}")
                                
                                # Extract description following DocC format
                                method_abstract = method_ref.get("abstract", [])
                                method_description = ""
                                if method_abstract and isinstance(method_abstract, list):
                                    method_description = " ".join([item.get("text", "") for item in method_abstract if isinstance(item, dict)])
                                elif isinstance(method_abstract, str):
                                    method_description = method_abstract
                                
                                # Extract detailed discussion from the loaded method file
                                method_details = method_description  # fallback to description
                                if method_data:
                                    # Look for discussion in primaryContentSections
                                    primary_sections = method_data.get("primaryContentSections", [])
                                    for section in primary_sections:
                                        if section.get("kind") == "content":
                                            content_items = section.get("content", [])
                                            discussion_parts = []
                                            for item in content_items:
                                                if isinstance(item, dict) and item.get("type") == "paragraph":
                                                    inline_content = item.get("inlineContent", [])
                                                    for inline_item in inline_content:
                                                        if isinstance(inline_item, dict) and inline_item.get("type") == "text":
                                                            discussion_parts.append(inline_item.get("text", ""))
                                            if discussion_parts:
                                                method_details = " ".join(discussion_parts)
                                                break
                                
                                # Extract return type from DocC returns section
                                return_type = {"id": "Void", "name": "Void"}
                                method_returns = method_ref.get("returns", {})
                                if method_returns:
                                    return_content = method_returns.get("content", [])
                                    if return_content:
                                        return_description = " ".join([item.get("text", "") for item in return_content if isinstance(item, dict)])
                                        # Try to extract return type from description or fragments
                                        if "Bool" in return_description:
                                            return_type = {"id": "Bool", "name": "Bool"}
                                        elif "String" in return_description:
                                            return_type = {"id": "String", "name": "String"}
                                        # Add more type detection as needed
                                
                                # Extract throws information
                                throws_info = None
                                method_throws = method_ref.get("throws", {})
                                if method_throws:
                                    throws_content = method_throws.get("content", [])
                                    if throws_content:
                                        throws_info = " ".join([item.get("text", "") for item in throws_content if isinstance(item, dict)])
                                
                                method_info = {
                                    "category": category,
                                    "description": method_description or f"{clean_method_name} method",
                                    "id": clean_method_name,
                                    "showDocs": True,
                                    "title": clean_method_name,
                                    "releaseTag": "public",
                                    "params": params,
                                    "returnType": return_type,
                                    "path": f"PostHog/{title}.swift"
                                }
                                
                                # Only add details if there's actual content
                                if method_details:
                                    method_info["details"] = method_details
                                
                                # Add throws information if available
                                if throws_info:
                                    method_info["throws"] = throws_info
                                
                                classes[title]["functions"].append(method_info)
        
        # Handle enums/structs
        elif (kind == "symbol" and symbol_kind in ["enum", "struct"] and "PostHog" in title):
            abstract = data.get("abstract", [])
            description = ""
            if abstract and isinstance(abstract, list):
                description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
            elif isinstance(abstract, str):
                description = abstract
            
            types[title] = {
                "id": title,
                "name": title,
                "description": description or f"{title} type",
                "properties": [],
                "path": f"PostHog/{title}.swift",
                "example": f"{title}()"
            }
    
    result["classes"] = list(classes.values())
    result["types"] = list(types.values())
    
    print(f"🔍 Processed DocC documentation")
    print(f"📋 Generated {len(classes)} classes and {len(types)} types")
    
    return result

def main():
    if len(sys.argv) != 4:
        print("Usage: python3 transform-docc.py <docc-data-directory> <output-docs.json> <version>")
        sys.exit(1)
    
    docc_data_dir = sys.argv[1]
    output_file = sys.argv[2]
    version = sys.argv[3]
    
    if not os.path.isdir(docc_data_dir):
        print(f"❌ Error: {docc_data_dir} is not a directory")
        sys.exit(1)
    
    try:
        # Process DocC directory
        result = process_docc_directory(docc_data_dir, version)
        
        # Dump the output to file
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2)
        
        print(f"✅ Successfully transformed {docc_data_dir} to {output_file}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
