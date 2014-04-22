/*
 * CocosBuilder: http://www.cocosbuilder.com
 *
 * Copyright (c) 2012 Zynga Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <Foundation/Foundation.h>
#import "PlugInManager.h"
#import "PlugInExport.h"

static void getLocalizedTextFromNode(NSDictionary* node, NSMutableDictionary* xmlDict)
{
    NSString* baseClassName = [node objectForKey:@"baseClass"];

    if([baseClassName isEqualToString:@"CCLabelTTF"] ||
       [baseClassName isEqualToString:@"CCLabelBMFont"] ||
       [baseClassName isEqualToString:@"CCLabelTTFv2"] ||
       [baseClassName isEqualToString:@"CCLabelBMFontv2"]) {

        NSArray* properties = [node objectForKey:@"properties"];

        NSString* localizationKey = @"";
        NSString* localizationText = @"";

        for (NSDictionary* prop in properties) {
            NSString* propName = [prop objectForKey:@"name"];
            if ([propName isEqualToString:@"instanceName"]) {
                localizationKey = [prop objectForKey:@"value"];
            }
            else if ([propName isEqualToString:@"string"]) {
                localizationText = [prop objectForKey:@"value"];
            }
        }

        [xmlDict setObject:localizationText forKey:localizationKey];
    }

    NSArray* children = [node objectForKey:@"children"];
    for (NSDictionary* child in children) {
        getLocalizedTextFromNode(child, xmlDict);
    }
}


static void	parseArgs(NSArray *args, NSString **outPlugin, NSArray **publishPaths, NSURL **outputPath, BOOL *verbose, NSURL **localizationPath)
{
	*outPlugin = @"ccbi";
	
	NSMutableArray		*paths = [NSMutableArray array];
	NSString			*prog = [args objectAtIndex:0];
	BOOL				stillParsingArgs = YES;
	
	for (NSInteger i = 1; i < args.count; ++i)
	{
		NSString		*arg = [args objectAtIndex:i];
		
		if (stillParsingArgs && ([arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]))
		{
			fprintf(stdout, "%s", [[NSString stringWithFormat:
@"Usage:\n"
@"%@ [-e <extension>|--extension=<extension>] [-o <outputfile>|--output=<outputfile>] [-v|--verbose] file\n"
@"%@ [-e <extension>|--extension=<extension>] [-o <outputdir>|--output=<outputdir>] [-v|--verbose] file1 [file2 ...]\n"
@"%@ -l <localizationdir>\n"
@"%@ -h|--help\n"
@"%@ --version\n", prog, prog, prog, prog, prog] UTF8String]);
			exit(EXIT_SUCCESS);
		}
		else if (stillParsingArgs && [arg isEqualToString:@"--version"])
		{
			fprintf(stdout, "%s", [[NSString stringWithFormat:
@"%@\n"
@"Version %@\n", prog, @"1.1"] UTF8String]); // do not hardcode me
			exit(EXIT_SUCCESS);
		}
		else if (stillParsingArgs && ([arg isEqualToString:@"-l"]))
			*localizationPath = [[NSURL fileURLWithPath:[args objectAtIndex:++i]] absoluteURL];
		else if (stillParsingArgs && ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]))
			*verbose = YES;
		else if (stillParsingArgs && [arg isEqualToString:@"-e"])
			*outPlugin = [args objectAtIndex:++i];
		else if (stillParsingArgs && [arg hasPrefix:@"-e"])
			*outPlugin = [arg substringFromIndex:2];
		else if (stillParsingArgs && [arg hasPrefix:@"--extension="])
			*outPlugin = [arg substringFromIndex:12];
			
		else if (stillParsingArgs && [arg isEqualToString:@"-o"])
			*outputPath = [[NSURL fileURLWithPath:[args objectAtIndex:++i]] absoluteURL];
		else if (stillParsingArgs && [arg hasPrefix:@"-o"])
			*outputPath = [[NSURL fileURLWithPath:[arg substringFromIndex:2]] absoluteURL];
		else if (stillParsingArgs && [arg hasPrefix:@"--output="])
			*outputPath = [[NSURL fileURLWithPath:[arg substringFromIndex:9]] absoluteURL];

		else if (stillParsingArgs && [arg isEqualToString:@"--"])
			stillParsingArgs = NO;
		else
		{
			stillParsingArgs = NO;
			[paths addObject:[[NSURL fileURLWithPath:arg] absoluteURL]];
		}
	}
	if ([paths count] < 1)
	{
		fprintf(stdout, "Error: Must provide at least one path to process.\n");
		exit(EXIT_FAILURE);
	}
	*publishPaths = paths;
}

int		main(int argc, const char **argv)
{
#if __clang_major__ >= 3
	@autoreleasepool
#else
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#endif
	{
		NSMutableArray			*args = [NSMutableArray array];
		
		// It is trivially possible to get the OS to pass non-UTF-8 arguments,
		//	but there is no immediate solution. For now, don't try to use this
		//	with a non-Unicode terminal.
		for (int i = 0; i < argc; ++i)
			[args addObject:[NSString stringWithUTF8String:argv[i]]];
		
		NSString				*pluginExt = nil;
		NSArray					*operands = nil;
		NSURL					*outputPath = nil;
		PlugInExport			*plugin = nil;
		BOOL					verbose = NO;
        NSURL                   *localizationPath = nil;
		
		[[PlugInManager sharedManager] loadPlugIns];
		parseArgs(args, &pluginExt, &operands, &outputPath, &verbose, &localizationPath);
		
		if (!(plugin = [[PlugInManager sharedManager] plugInExportForExtension:pluginExt]))
		{
			fprintf(stdout, "Error: No plugin exists using the extension %s.\n", [pluginExt UTF8String]);
			exit(EXIT_FAILURE);
		}
		
		NSInteger				succeeds = 0, failures = 0;
		
		for (NSURL *file in operands)
		{
			NSDictionary		*dict = [NSDictionary dictionaryWithContentsOfURL:file];
			
			if (!dict)
			{
				++failures;
				fprintf(stderr, "Error: Failed reading file %s.\n", [[file absoluteString] UTF8String]);
				continue;
			}
			
			NSData				*outData = [plugin exportDocumentDefault:dict];
			
			if (!outData)
			{
				++failures;
				fprintf(stderr, "Error: Failed exporting file %s.\n", [[file absoluteString] UTF8String]);
				continue;
			}
			
			NSURL				*outFile = nil;

            if (outputPath == nil) // no output path and however many files: construct file name in file's dir
				outFile = [[file URLByDeletingPathExtension] URLByAppendingPathExtension:plugin.extension];
			else if (operands.count == 1) // output path and only one file: use output verbatim
				outFile = outputPath;
			else // output path and multiple files: use file's name in output path
			{
				outFile = [[[outputPath URLByAppendingPathComponent:file.lastPathComponent] URLByDeletingPathExtension]
					URLByAppendingPathExtension:plugin.extension];
			}

            if (![outData writeToURL:outFile options:NSDataWritingAtomic error:nil])
			{
				fprintf(stderr, "Error: Failed writing %s to %s.\n", [[file absoluteString] UTF8String], [[outFile absoluteString] UTF8String]);
				++failures;
			}
			else
			{
				if (verbose)
					fprintf(stderr, "Notice: Successfully processed %s.\n", [[file absoluteString] UTF8String]);
				++succeeds;
			}

            if (localizationPath) {
                /*

                 Publish Localization XML

                 */

                // Get localization texts from node graph.
                NSMutableDictionary* localiztionXmlDict = [[NSMutableDictionary alloc] init];
                NSDictionary* nodeGraph = [dict objectForKey:@"nodeGraph"];

                NSString* strippedFileName = [[outputPath lastPathComponent] stringByDeletingPathExtension];
                NSString* localizationDirectory = [localizationPath lastPathComponent];

                getLocalizedTextFromNode(nodeGraph, localiztionXmlDict);

                if ([[localiztionXmlDict allKeys] count] != 0) {
                    // Write localization texts to file
                    NSMutableString* localizationFileStr = [[NSMutableString alloc] init];

                    [localizationFileStr appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"];
                    [localizationFileStr appendString:@"<resources xmlns:tools=\"http://schemas.android.com/tools\">\n"];

                    for (NSString* key in localiztionXmlDict) {
                        [localizationFileStr appendFormat:@"    <string name=\"%@\"><![CDATA[%@]]></string>\n", key, [localiztionXmlDict objectForKey:key]];
                    }

                    [localizationFileStr appendString:@"</resources>"];

                    NSFileManager* fileManager= [NSFileManager defaultManager];
                    if(![fileManager fileExistsAtPath:localizationDirectory isDirectory:NO]){
                        if(![fileManager createDirectoryAtPath:localizationDirectory withIntermediateDirectories:YES attributes:nil error:NULL]){
                            NSLog(@"Error: Create folder failed %@", localizationDirectory);
                        }
                    }

                    NSString* docFile = [localizationDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.xml", strippedFileName]];

                    BOOL localizationXmlPublishSuccessful = [localizationFileStr writeToFile:docFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    if (!localizationXmlPublishSuccessful)
                    {
                        NSLog(@"Failed to  Publish Localization Xml");
                    }
                }
            }

		}
		
		if (verbose)
			fprintf(stderr, "Done processing. %ld files succeeded, %ld files failed.\n", succeeds, failures);
		exit(failures ? EXIT_FAILURE : EXIT_SUCCESS);
	}
#if __clang_major__ < 3
	[pool drain];
#endif
	return 0;
}