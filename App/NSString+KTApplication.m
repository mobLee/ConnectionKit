//
//  NSString+KTApplication.m
//  Marvel
//
//  Created by Dan Wood on 7/28/05.
//  Copyright (c) 2005 Biophony LLC. All rights reserved.
//

#import "NSString+KTApplication.h"

#import "NSCharacterSet+Karelia.h"

@implementation NSString ( KTApplication )

/*!	Return the last two components of an email address or host name. Returns nil if no domain name found
*/
- (NSString *)domainName
{
	NSString *result = nil;
	
	NSRange lastDot = [self rangeOfString:@"." options:NSBackwardsSearch];
	if (NSNotFound != lastDot.location)
	{
		static NSCharacterSet *sEarlierDelimSet = nil;
		if (nil == sEarlierDelimSet)
		{
			sEarlierDelimSet = [[NSCharacterSet characterSetWithCharactersInString:@".@"] retain];
		}
		
		NSRange earlierDelim = [self rangeOfCharacterFromSet:sEarlierDelimSet options:NSBackwardsSearch range:NSMakeRange(0,lastDot.location)];
		if (NSNotFound != earlierDelim.location)
		{
			result = [self substringFromIndex:earlierDelim.location+1];
			// return string after the @ or the . to the end of the string
		}
		else
		{
			result = self;	// didn't find earlier delimeter, so string must be domain.tld
		}
	}
	return result;
}

- (BOOL) looksLikeValidHost
{
	if ([self isEqualToString:@"localhost"]) return YES;

	static NSCharacterSet *sIllegalHostNameSet = nil;
	static NSCharacterSet *sIllegalIPAddressSet = nil;
	if (nil == sIllegalHostNameSet)
	{
		sIllegalHostNameSet = [[[[NSCharacterSet alphanumericASCIICharacterSet] setByAddingCharactersInString:@".-"] invertedSet] retain];
		sIllegalIPAddressSet = [[[NSCharacterSet characterSetWithCharactersInString:@".0123456789"] invertedSet] retain];
	}
	
	NSRange whereBad = [self rangeOfCharacterFromSet:sIllegalHostNameSet];
	if (NSNotFound != whereBad.location)
	{
		return NO;
	}
	// now more rigorous test.
	NSArray *components = [self componentsSeparatedByString:@"."];
	
	NSRange whereBadIPAddress = [self rangeOfCharacterFromSet:sIllegalIPAddressSet];
	if (NSNotFound == whereBadIPAddress.location)
	{
		if ([components count] != 4)
		{
			return NO;	// we must have at 4 items
		}
		// We have a potential IP address, numbers only between the decimals
		NSEnumerator *theEnum = [components objectEnumerator];
		id num;
		
		while (nil != (num = [theEnum nextObject]) )
		{
			if ([num isEqualToString:@""] || [num intValue] > 255)
			{
				return NO;
			}
		}
	}
	else	// Non IP address, look for foo.bar.baz pattern
	{
		if ([components count] < 2)
		{
			return ([[self lowercaseString] isEqualToString:@"localhost"]);
			// Only localhost works if less than two components
		}
		NSString *lastComponent = [components lastObject];
		if ([lastComponent length] < 2 || ( NSNotFound != [lastComponent rangeOfString:@"-"].location) )
		{
			return NO;	// last item can't be shorter than 2 characters, can't have dash
		}
		if ([((NSString *)[components lastObject]) length] < 2)
		{
			return NO;	// last item can't be shorter than 2 characters
		}
		NSEnumerator *theEnum = [components	objectEnumerator];
		id component;
		
		while (nil != (component = [theEnum nextObject]) )
		{
			if ([component isEqualToString:@""] || [component hasPrefix:@"-"] || [component hasSuffix:@"-"])
			{
				return NO;	// two dots in a row, meaning empty inbetween, is bad.  Prefix or suffix of - is bad.
			}
		}
	}
	return YES;
}

@end

