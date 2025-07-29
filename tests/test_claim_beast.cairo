#[cfg(test)]
mod test_claim_beast {
    use core::traits::Into;
    
    // Test the 4% probability calculations used in claim_beast
    #[test]
    fn test_shiny_probability_calculation() {
        // Test various seeds to verify the 4% probability logic
        
        // Case 1: Seed that should produce shiny (lower 32 bits < 400)
        let seed1 = 0x0000000000000001_u64;
        let shiny_seed1 = (seed1 & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_seed1 == 1, 'Shiny seed1 should be 1');
        assert(shiny_seed1 < 400_u64, 'Should be shiny');
        
        // Case 2: Seed at exact boundary (400)
        let seed2 = 0x0000000000000190_u64; // 0x190 = 400
        let shiny_seed2 = (seed2 & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_seed2 == 400, 'Shiny seed2 should be 400');
        assert(shiny_seed2 >= 400_u64, 'Should not be shiny');
        
        // Case 3: Large seed that wraps around
        let seed3 = 0x0000000000002710_u64; // 10000 % 10000 = 0
        let shiny_seed3 = (seed3 & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_seed3 == 0, 'Shiny seed3 should be 0');
        assert(shiny_seed3 < 400_u64, 'Should be shiny');
    }
    
    #[test]
    fn test_animated_probability_calculation() {
        // Test animated trait calculation (upper 32 bits)
        
        // Case 1: Seed with animated trait
        let seed1 = 0x0000000100000000_u64; // Upper 32 bits = 1
        let animated_seed1 = ((seed1 / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        assert(animated_seed1 == 1, 'Animated seed1 should be 1');
        assert(animated_seed1 < 400_u64, 'Should be animated');
        
        // Case 2: Seed at boundary
        let seed2 = 0x0000019000000000_u64; // Upper bits = 0x190 = 400
        let animated_seed2 = ((seed2 / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        assert(animated_seed2 == 400, 'Animated seed2 should be 400');
        assert(animated_seed2 >= 400_u64, 'Should not be animated');
    }
    
    #[test]
    fn test_both_traits_calculation() {
        // Test seed that produces both shiny and animated
        let seed = 0x000000FF000000FF_u64; // Both parts < 400
        
        let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_seed == 255, 'Shiny should be 255');
        assert(shiny_seed < 400_u64, 'Should be shiny');
        
        let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        assert(animated_seed == 255, 'Animated should be 255');
        assert(animated_seed < 400_u64, 'Should be animated');
    }
    
    #[test]
    fn test_no_traits_calculation() {
        // Test seed that produces neither trait
        let seed = 0x0000FFFF0000FFFF_u64; // Both parts > 400
        
        let shiny_seed = (seed & 0xFFFFFFFF_u64) % 10000_u64;
        assert(shiny_seed == 0xFFFF % 10000, 'Shiny calculation');
        assert(shiny_seed >= 400_u64, 'Should not be shiny');
        
        let animated_seed = ((seed / 0x100000000_u64) & 0xFFFFFFFF_u64) % 10000_u64;
        assert(animated_seed == 0xFFFF % 10000, 'Animated calculation');
        assert(animated_seed >= 400_u64, 'Should not be animated');
    }
    
    #[test]
    fn test_4_percent_rate_verification() {
        // Verify that 400 out of 10000 = 4%
        let threshold = 400_u64;
        let total_range = 10000_u64;
        let rate_percent = threshold * 100 / total_range;
        assert(rate_percent == 4, 'Should be 4% rate');
        
        // Test edge cases
        assert(399_u64 < threshold, '399 should trigger trait');
        assert(400_u64 >= threshold, '400 should not trigger trait');
        
        // Count how many values < 400 in first 1000
        let mut count = 0_u32;
        let mut i = 0_u64;
        loop {
            if i >= 1000_u64 {
                break;
            }
            if i < threshold {
                count += 1;
            }
            i += 1;
        };
        
        // Should be exactly 400 values < 400 in first 1000
        assert(count == 400, 'Should be 400 in first 1000');
    }
    
    #[test]
    fn test_beast_hash_calculation() {
        // Test the hash calculation logic
        let beast_id: u8 = 5;
        let prefix: u8 = 10;
        let suffix: u8 = 15;
        
        let expected_hash: felt252 = (beast_id.into() * 10000 + prefix.into() * 100 + suffix.into()).into();
        let calculated: u32 = 5 * 10000 + 10 * 100 + 15;
        
        assert(calculated == 51015, 'Hash calculation wrong');
        assert(expected_hash == 51015, 'Hash should be 51015');
    }
}