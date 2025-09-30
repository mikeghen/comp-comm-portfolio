import React from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Navbar, Nav, Container, Badge } from 'react-bootstrap';

interface HeaderProps {
  currentPage?: 'portfolio' | 'policy';
  onNavigate?: (page: 'portfolio' | 'policy') => void;
}

function Header({ currentPage = 'portfolio', onNavigate }: HeaderProps) {
  const handleNavigation = (page: 'portfolio' | 'policy') => {
    if (onNavigate) {
      onNavigate(page);
    }
  };

  return (
    <Navbar bg="success" variant="dark" expand="lg" sticky="top">
      <Container>
        <Navbar.Brand 
          href="#" 
          onClick={(e) => {
            e.preventDefault();
            handleNavigation('portfolio');
          }}
          style={{ cursor: 'pointer' }}
        >
          Compound Community Portfolio <Badge bg="warning" text="dark">Beta</Badge>
        </Navbar.Brand>
        <Navbar.Toggle aria-controls="basic-navbar-nav" />
        <Navbar.Collapse id="basic-navbar-nav" className="justify-content-between">
          <Nav className="me-auto">
            <Nav.Link 
              href="#"
              onClick={(e) => {
                e.preventDefault();
                handleNavigation('policy');
              }}
              className={currentPage === 'policy' ? 'active' : ''}
            >
              Policy
            </Nav.Link>
            <Nav.Link href="https://www.comp.xyz/t/compound-community-portfolio-pay-to-govern-p2g-experiment/7228" target="_blank" rel="noopener noreferrer">
              About
            </Nav.Link>
          </Nav>
          <div className="wallet-connect-container">
            <ConnectButton />
          </div>
        </Navbar.Collapse>
      </Container>
    </Navbar>
  );
}

export default Header; 